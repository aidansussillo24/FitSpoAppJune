import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    // The user ID whose profile is shown
    let userId: String

    // MARK: – State
    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var avatarURL: String = ""
    @State private var email: String = ""
    @State private var posts: [Post] = []
    @State private var followersCount: Int = 0
    @State private var followingCount: Int = 0
    @State private var isFollowing: Bool = false
    @State private var isLoadingPosts: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingEdit: Bool = false

    private let db = Firestore.firestore()

    // Two-column layout for posts
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Avatar
                    avatarSection

                    // Name, Email & Bio
                    VStack(spacing: 4) {
                        Text(displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !bio.isEmpty {
                            Text(bio)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    // Stats Row: Followers, Following, Posts
                    HStack(spacing: 32) {
                        // Followers link (blue)
                        NavigationLink(destination: FollowersView(userId: userId)) {
                            statView(count: followersCount, label: "Followers")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Following link (blue)
                        NavigationLink(destination: FollowingView(userId: userId)) {
                            statView(count: followingCount, label: "Following")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Posts count (black)
                        statView(count: posts.count, label: "Posts")
                            .foregroundColor(.primary)
                    }

                    // Action Button
                    if userId == Auth.auth().currentUser?.uid {
                        Button("Edit Profile") {
                            showingEdit = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    } else {
                        Button(isFollowing ? "Unfollow" : "Follow") {
                            toggleFollow()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Divider().padding(.vertical, 8)

                    // Posts Grid (clickable)
                    if isLoadingPosts {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(posts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    PostCell(post: post)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(displayName.isEmpty ? "Profile" : displayName)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        try? Auth.auth().signOut()
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                EditProfileView()
            }
            .onAppear(perform: loadEverything)
        }
    }
}

private extension ProfileView {
    // Single stat view (count + label)
    func statView(count: Int, label: String) -> some View {
        VStack {
            Text("\(count)")
                .font(.headline)
            Text(label)
                .font(.caption)
        }
    }

    // Avatar section with AsyncImage
    var avatarSection: some View {
        Group {
            if let url = URL(string: avatarURL), !avatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView()
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    case .failure:
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .resizable()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.gray)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 120, height: 120)
        .padding(.top, 16)
    }

    // Load everything
    func loadEverything() {
        loadProfile()
        loadUserPosts()
        loadFollowState()
        loadFollowCounts()
    }

    func loadProfile() {
        guard let me = Auth.auth().currentUser else { return }
        email = me.email ?? ""
        db.collection("users").document(userId).getDocument { snap, err in
            if let err = err {
                errorMessage = err.localizedDescription; return
            }
            guard let d = snap?.data() else { return }
            displayName = d["displayName"] as? String ?? ""
            bio         = d["bio"]         as? String ?? ""
            avatarURL   = d["avatarURL"]   as? String ?? ""
        }
    }

    func loadUserPosts() {
        isLoadingPosts = true
        NetworkService.shared.fetchPosts { result in
            DispatchQueue.main.async {
                isLoadingPosts = false
                switch result {
                case .success(let all):
                    posts = all.filter { $0.userId == userId }
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }

    func loadFollowState() {
        NetworkService.shared.isFollowing(userId: userId) { result in
            if case .success(let f) = result {
                isFollowing = f
            }
        }
    }

    func loadFollowCounts() {
        NetworkService.shared.fetchFollowCount(userId: userId, type: "followers") { result in
            if case .success(let c) = result {
                followersCount = c
            }
        }
        NetworkService.shared.fetchFollowCount(userId: userId, type: "following") { result in
            if case .success(let c) = result {
                followingCount = c
            }
        }
    }

    func toggleFollow() {
        let action = isFollowing
            ? NetworkService.shared.unfollow
            : NetworkService.shared.follow
        action(userId) { err in
            if let err = err {
                errorMessage = err.localizedDescription
            } else {
                isFollowing.toggle()
                loadFollowCounts()
            }
        }
    }
}
