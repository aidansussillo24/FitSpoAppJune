import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

struct PostDetailView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss

    // ─── Author Info ────────────────────────────
    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    // ─── Location Name ──────────────────────────
    @State private var locationName    = ""

    // ─── Delete State ───────────────────────────
    @State private var isDeleting        = false
    @State private var showDeleteConfirm = false

    // ─── Like State ─────────────────────────────
    @State private var isLiked    : Bool
    @State private var likesCount : Int

    // ─── Comment Placeholder ────────────────────
    @State private var commentCount : Int = 0

    // MARK: – Init from Post
    init(post: Post) {
        self.post = post
        _isLiked    = State(initialValue: post.isLiked)
        _likesCount = State(initialValue: post.likes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: – Header: Avatar, Name & Location
                HStack(alignment: .top, spacing: 12) {
                    // Avatar tappable to profile
                    NavigationLink(destination: ProfileView(userId: post.userId)) {
                        if let url = URL(string: authorAvatarURL), !authorAvatarURL.isEmpty {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:     ProgressView()
                                case .success(let img):
                                    img
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
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
                        }
                    }

                    // Name & location
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink(destination: ProfileView(userId: post.userId)) {
                            Text(isLoadingAuthor ? "Loading…" : authorName)
                                .font(.headline)
                        }
                        if !locationName.isEmpty {
                            Text(locationName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal)

                // MARK: – Post Image
                AsyncImage(url: URL(string: post.imageURL)) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.gray.opacity(0.2)
                            ProgressView()
                        }
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        ZStack {
                            Color.gray.opacity(0.2)
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()

                // MARK: – Actions: Like, Comment & DM
                HStack(spacing: 24) {
                    // Like
                    Button(action: toggleLike) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundColor(isLiked ? .red : .primary)
                    }
                    Text("\(likesCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    // Comment (placeholder)
                    Button(action: {
                        // TODO: navigate to comments screen
                    }) {
                        Image(systemName: "bubble.right")
                            .font(.title2)
                    }
                    Text("\(commentCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    // DM
                    Button(action: {
                        // TODO: navigate to direct message flow
                    }) {
                        Image(systemName: "paperplane")
                            .font(.title2)
                    }

                    Spacer()
                }
                .padding(.horizontal)

                // MARK: – Caption
                HStack(alignment: .top, spacing: 4) {
                    NavigationLink(destination: ProfileView(userId: post.userId)) {
                        Text(isLoadingAuthor ? "Loading…" : authorName)
                            .fontWeight(.semibold)
                    }
                    Text(post.caption)
                }
                .padding(.horizontal)

                // MARK: – Timestamp
                Text(post.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)

                Spacer(minLength: 32)
            }
            .padding(.top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Delete button for post owner
            if post.userId == Auth.auth().currentUser?.uid {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .alert("Delete Post?", isPresented: $showDeleteConfirm) {
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
        .onAppear {
            fetchAuthor()
            fetchLocationName()
        }
    }

    // MARK: – Fetch Author Info
    private func fetchAuthor() {
        let db = Firestore.firestore()
        db.collection("users")
          .document(post.userId)
          .getDocument { snap, err in
            isLoadingAuthor = false
            guard err == nil, let data = snap?.data() else {
                authorName = "Unknown"
                return
            }
            authorName = data["displayName"] as? String ?? "Unknown"
            // support either field name
            let a1 = data["avatarURL"] as? String
            let a2 = data["photoURL"]  as? String
            authorAvatarURL = a1 ?? a2 ?? ""
        }
    }

    // MARK: – Reverse Geocode Post Location
    private func fetchLocationName() {
        guard let lat = post.latitude,
              let lon = post.longitude else { return }
        let loc = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(loc) { places, _ in
            guard let place = places?.first else { return }
            var parts: [String] = []
            if let city = place.locality          { parts.append(city) }
            if let region = place.administrativeArea { parts.append(region) }
            if parts.isEmpty, let country = place.country {
                parts.append(country)
            }
            locationName = parts.joined(separator: ", ")
        }
    }

    // MARK: – Toggle Like
    private func toggleLike() {
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        NetworkService.shared.toggleLike(post: post) { _ in }
    }

    // MARK: – Delete
    private func performDelete() {
        isDeleting = true
        NetworkService.shared.deletePost(id: post.id) { result in
            DispatchQueue.main.async {
                isDeleting = false
                if case .success = result {
                    dismiss()
                }
            }
        }
    }
}

#if DEBUG
struct PostDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PostDetailView(
                post: Post(
                    id:        "1",
                    userId:    "u123",
                    imageURL:  "https://via.placeholder.com/600",
                    caption:   "What the dog doing?",
                    timestamp: Date(),
                    likes:     3,
                    isLiked:   false,
                    latitude:  40.7128,
                    longitude: -74.0060
                )
            )
        }
    }
}
#endif
