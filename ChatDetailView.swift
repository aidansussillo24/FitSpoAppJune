import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatDetailView: View {
    let chat: Chat

    @State private var messages: [Message] = []
    @State private var newText: String = ""
    @State private var listener: ListenerRegistration?
    @State private var profiles: [String:(displayName:String, avatarURL:String)] = [:]

    // Current user ID
    private var meUid: String? {
        Auth.auth().currentUser?.uid
    }

    // The other participant’s UID
    private var otherId: String {
        guard let me = meUid else { return "" }
        return chat.participants.first { $0 != me } ?? ""
    }

    // Display name in the nav bar
    private var navTitle: String {
        profiles[otherId]?.displayName ?? otherId
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { msg in
                            HStack(alignment: .bottom, spacing: 8) {
                                if msg.senderId != meUid {
                                    // Incoming message: avatar, bubble, spacer
                                    avatarView(userId: msg.senderId, size: 32)
                                    messageBubble(for: msg, incoming: true)
                                    Spacer()
                                } else {
                                    // Outgoing message: spacer, bubble
                                    Spacer()
                                    messageBubble(for: msg, incoming: false)
                                }
                            }
                            .id(msg.id)
                            .onAppear { loadProfile(userId: msg.senderId) }
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            // Composer
            HStack {
                TextField("Message…", text: $newText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Send") {
                    send()
                }
                .disabled(newText.isEmpty)
            }
            .padding()
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startListening()
            loadProfile(userId: otherId)
        }
        .onDisappear {
            listener?.remove()
        }
    }

    // MARK: – Message bubble view
    private func messageBubble(for msg: Message, incoming: Bool) -> some View {
        Text(msg.text)
            .padding(10)
            .background(incoming
                        ? Color.gray.opacity(0.2)
                        : Color.blue.opacity(0.2))
            .cornerRadius(10)
    }

    // MARK: – Avatar helper
    @ViewBuilder
    private func avatarView(userId: String, size: CGFloat) -> some View {
        if let profile = profiles[userId],
           let url = URL(string: profile.avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty: ProgressView()
                case .success(let img): img.resizable().scaledToFill()
                case .failure: Image(systemName: "person.crop.circle.fill").resizable().scaledToFill()
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

    // MARK: – Load profile data
    private func loadProfile(userId: String) {
        guard profiles[userId] == nil else { return }
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .getDocument { snap, err in
                guard err == nil, let data = snap?.data() else { return }
                let name   = data["displayName"] as? String ?? userId
                let avatar = data["avatarURL"]   as? String ?? ""
                DispatchQueue.main.async {
                    profiles[userId] = (displayName: name, avatarURL: avatar)
                }
            }
    }

    // MARK: – Real‐time listener
    private func startListening() {
        listener = NetworkService.shared.observeMessages(chatId: chat.id) { result in
            switch result {
            case .success(let msg):
                DispatchQueue.main.async {
                    messages.append(msg)
                }
            case .failure(let err):
                print("Msg listener error:", err)
            }
        }
    }

    // MARK: – Send a new message
    private func send() {
        let text = newText
        newText = ""
        NetworkService.shared.sendMessage(chatId: chat.id, text: text) { error in
            if let error = error {
                print("Send error:", error)
            }
        }
    }
}

struct ChatDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ChatDetailView(
                chat: Chat(
                    id: "chat1",
                    participants: ["u1","u2"],
                    lastMessage: "Hello",
                    lastTimestamp: Date()
                )
            )
        }
    }
}
