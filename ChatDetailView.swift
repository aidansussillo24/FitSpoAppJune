//
//  ChatDetailView.swift
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatDetailView: View {
    let chat: Chat

    @State private var messages: [Message] = []
    @State private var newText: String     = ""
    @State private var listener: ListenerRegistration?

    // cache other users’ profiles
    @State private var profiles: [String:(displayName:String,avatarURL:String)] = [:]

    private var meUid: String { Auth.auth().currentUser?.uid ?? "" }
    private var otherId: String {
        chat.participants.first { $0 != meUid } ?? ""
    }
    private var navTitle: String {
        profiles[otherId]?.displayName ?? "…"
    }

    var body: some View {
        VStack {
            // ─── Message list ─────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { msg in
                            HStack(alignment: .bottom, spacing: 8) {
                                if msg.senderId != meUid {
                                    avatar(for: msg.senderId, size: 32)
                                    messageBubble(msg, incoming: true)
                                    Spacer()
                                } else {
                                    Spacer()
                                    messageBubble(msg, incoming: false)
                                }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: messages.count) { _ in
                    if let lastID = messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            // ─── Composer ─────────────────────────────────────
            HStack {
                TextField("Message…", text: $newText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Send") {
                    let txt = newText.trimmingCharacters(in: .whitespaces)
                    guard !txt.isEmpty else { return }
                    newText = ""
                    NetworkService.shared.sendMessage(
                        chatId: chat.id,
                        text: txt
                    ) { _ in }
                }
                .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // start listener
            listener = NetworkService.shared.observeMessages(
                chatId: chat.id
            ) { result in
                switch result {
                case .success(let m):
                    DispatchQueue.main.async { messages.append(m) }
                case .failure(let err):
                    print("Msg listen error:", err)
                }
            }
            // preload the other user’s profile
            loadProfile(userId: otherId)
        }
        .onDisappear {
            listener?.remove()
        }
    }

    // MARK: – Helpers

    @ViewBuilder
    private func avatar(for userId: String, size: CGFloat) -> some View {
        if let p = profiles[userId],
           let url = URL(string: p.avatarURL)
        {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:     ProgressView()
                case .success(let img): img.resizable().scaledToFill()
                case .failure:    Image(systemName: "person.crop.circle.fill").resizable()
                @unknown default: EmptyView()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundColor(.gray)
                .clipShape(Circle())
        }
    }

    private func messageBubble(_ msg: Message, incoming: Bool) -> some View {
        let txt = msg.text ?? "[Photo]"
        return Text(txt)
            .padding(10)
            .background(incoming
                        ? Color.gray.opacity(0.2)
                        : Color.blue.opacity(0.8))
            .foregroundColor(incoming ? .primary : .white)
            .cornerRadius(12)
    }

    private func loadProfile(userId: String) {
        guard profiles[userId] == nil else { return }
        Firestore.firestore().collection("users")
            .document(userId)
            .getDocument { snap, err in
                guard err == nil,
                      let d = snap?.data()
                else { return }
                let name   = d["displayName"] as? String ?? userId
                let avatar = d["avatarURL"]   as? String ?? ""
                DispatchQueue.main.async {
                    profiles[userId] = (displayName: name, avatarURL: avatar)
                }
            }
    }
}
