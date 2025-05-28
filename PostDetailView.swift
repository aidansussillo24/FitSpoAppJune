import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PostDetailView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss

    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true
    @State private var isDeleting      = false
    @State private var deleteError     : String?

    var body: some View {
        VStack(spacing: 16) {
            // MARK: – Author header
            HStack(spacing: 12) {
                if let url = URL(string: authorAvatarURL),
                   !authorAvatarURL.isEmpty
                {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:     ProgressView()
                        case .success(let img):
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                        @unknown default: EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            // MARK: – Tappable author name
            NavigationLink {
                ProfileView(userId: post.userId)
            } label: {
                Text(isLoadingAuthor ? "Loading…" : authorName)
                    .font(.headline)
            }

            // MARK: – The post’s image
            AsyncImage(url: URL(string: post.imageURL)) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(maxHeight: 300)
                case .success(let img):
                    img.resizable().scaledToFit()
                case .failure:
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                @unknown default:
                    EmptyView()
                }
            }

            // MARK: – Caption
            Text(post.caption)
                .font(.body)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Show Delete if this is _your_ post
            if post.userId == Auth.auth().currentUser?.uid {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        confirmDelete()
                    } label: {
                        Text("Delete")
                    }
                }
            }
        }
        .alert("Delete Post?", isPresented: $showingConfirm) {
            Button("Delete", role: .destructive, action: performDelete)
            Button("Cancel", role: .cancel) { }
        }
        .overlay {
            if isDeleting {
                ProgressView("Deleting…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear(perform: fetchAuthor)
    }

    // MARK: – Confirmation Alert
    @State private var showingConfirm = false
    private func confirmDelete() { showingConfirm = true }

    private func performDelete() {
        isDeleting = true
        NetworkService.shared.deletePost(id: post.id) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success:
                    dismiss()
                case .failure(let err):
                    deleteError = err.localizedDescription
                }
            }
        }
    }

    // MARK: – Fetch Author
    private func fetchAuthor() {
        let db = Firestore.firestore()
        db.collection("users")
          .document(post.userId)
          .getDocument { snap, err in
            isLoadingAuthor = false
            guard err == nil, let data = snap?.data() else { return }
            authorName      = data["displayName"] as? String ?? "Unknown"
            authorAvatarURL = data["avatarURL"]   as? String ?? ""
        }
    }
}

struct PostDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PostDetailView(
                post: Post(
                    id:        "123",
                    userId:    Auth.auth().currentUser?.uid ?? "u1",
                    imageURL:  "https://via.placeholder.com/600",
                    caption:   "Sample caption",
                    timestamp: Date(),
                    likes:     42,
                    isLiked:   false,
                    latitude:  nil,
                    longitude: nil
                )
            )
        }
    }
}
