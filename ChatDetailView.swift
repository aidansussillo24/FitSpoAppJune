import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatDetailView: View {
    let chat: Chat

    @State private var messages: [Message] = []
    @State private var newText: String = ""
    @State private var listener: ListenerRegistration?
    @State private var profiles: [String:(displayName:String, avatarURL:String)] = [:]

    // Determine the “other” user’s UID by excluding our own
    private var otherId: String {
        guard let meUid = Auth.auth().currentUser?.uid else { return "" }
        return chat.participants.first { $0 != meUid } ?? ""
    }

    // Show their displayName (or fallback to UID)
    private var navTitle: String {
        profiles[otherId]?.displayName ?? otherId
    }

    var body: some View {
        VStack {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { msg in
                            HStack(alignment: .bottom, spacing: 8) {
                                // Incoming message: avatar + bubble + spacer
                                if let meUid = Auth.auth().currentUser?.uid,
                                   msg.senderId != meUid {
                                    avatarView(userId: msg.senderId, size: 32)
                                } else {
                                    Spacer()
                                }

                                Text(msg.text)
                                    .padding()
                                    .background(
                                        (Auth.auth().currentUser?.uid == msg.senderId)
                                            ? Color.blue.opacity(0.2)
                                            : Color.gray.opacity(0.2)
                                    )
                                    .cornerRadius(8)

                                // Outgoing message: spacer + bubble
                                if let meUid = Auth.auth().currentUser?.uid,
                                   msg.senderId == meUid {
                                    Spacer()
                                }
                            }
                            .id(msg.id)
                            .onAppear {
                                loadProfile(userId: msg.senderId)
                            }
                        }
                    }
                    .padding()
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
                Button("Send") { send() }
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

    // MARK: – Load a user’s profile into our cache
    private func loadProfile(userId: String) {
        guard profiles[userId] == nil else { return }
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .getDocument { snap, err in
                guard err == nil, let d = snap?.data() else { return }
                let name   = d["displayName"] as? String ?? userId
                let avatar = d["avatarURL"]   as? String ?? ""
                DispatchQueue.main.async {
                    profiles[userId] = (displayName: name, avatarURL: avatar)
                }
            }
    }

    // MARK: – Real‐time listener for new messages
    private func startListening() {
        listener = NetworkService.shared.observeMessages(chatId: chat.id) { result in
            switch result {
            case .success(let msg):
                DispatchQueue.main.async { messages.append(msg) }
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
                    participants: ["u1", "u2"],
                    lastMessage: "Hello!",
                    lastTimestamp: Date()
                )
            )
        }
    }
}
