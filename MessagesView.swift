import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MessagesView: View {
    @State private var chats: [Chat] = []
    @State private var isLoading = false
    // caches other user profiles: userId → (displayName, avatarURL)
    @State private var profiles: [String: (displayName: String, avatarURL: String)] = [:]

    var body: some View {
        NavigationView {
            List(chats) { chat in
                let otherId = chat.participants.first { $0 != Auth.auth().currentUser?.uid } ?? ""
                NavigationLink(destination: ChatDetailView(chat: chat)) {
                    HStack(spacing: 12) {
                        // avatar
                        if let profile = profiles[otherId],
                           let url = URL(string: profile.avatarURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty: ProgressView()
                                case .success(let img): img.resizable().scaledToFill()
                                case .failure: Image(systemName: "person.crop.circle.fill").resizable().scaledToFill()
                                @unknown default: EmptyView()
                                }
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.gray)
                                .clipShape(Circle())
                        }

                        // name + last message
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profiles[otherId]?.displayName ?? otherId)
                                .font(.headline)
                            Text(chat.lastMessage)
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .onAppear {
                    loadProfile(userId: otherId)
                }
            }
            .navigationTitle("Messages")
            .onAppear(perform: loadChats)
        }
    }

    private func loadChats() {
        guard !isLoading else { return }
        isLoading = true
        NetworkService.shared.fetchChats { result in
            DispatchQueue.main.async {
                isLoading = false
                if case .success(let fetched) = result {
                    chats = fetched
                }
            }
        }
    }

    private func loadProfile(userId: String) {
        guard profiles[userId] == nil else { return }
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .getDocument { snap, err in
                guard err == nil, let d = snap?.data() else { return }
                let name   = d["displayName"] as? String ?? ""
                let avatar = d["avatarURL"]   as? String ?? ""
                DispatchQueue.main.async {
                    profiles[userId] = (displayName: name, avatarURL: avatar)
                }
            }
    }
}

struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        MessagesView()
    }
}
