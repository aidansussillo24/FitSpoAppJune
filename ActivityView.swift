import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ActivityView: View {
    @State private var notifications: [UserNotification] = []
    @State private var listener: ListenerRegistration?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            if notifications.isEmpty && !isLoading {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "bell")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No activity yet")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("When you get likes, comments, or mentions, they'll appear here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedNotifications.keys.sorted(by: { sectionOrder[$0] ?? 0 < sectionOrder[$1] ?? 0 }), id: \.self) { section in
                            if let sectionNotifications = groupedNotifications[section] {
                                VStack(spacing: 0) {
                                    // Section header
                                    HStack {
                                        Text(section)
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                    
                                    // Section content
                                    VStack(spacing: 0) {
                                        ForEach(sectionNotifications) { notification in
                                            ActivityRow(notification: notification)
                                            
                                            if notification.id != sectionNotifications.last?.id {
                                                Divider()
                                                    .padding(.leading, 72)
                                            }
                                        }
                                    }
                                    .background(Color(.systemBackground))
                                }
                                
                                if section != groupedNotifications.keys.sorted(by: { sectionOrder[$0] ?? 0 < sectionOrder[$1] ?? 0 }).last {
                                    Divider()
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("🔍 Test") {
                    testFollowNotification()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
            }
        }
        .refreshable {
            await refreshNotifications()
        }
        .onAppear(perform: attach)
        .onDisappear { listener?.remove(); listener = nil }
    }
    
    private var groupedNotifications: [String: [UserNotification]] {
        Dictionary(grouping: notifications) { $0.timeSection }
    }
    
    private var sectionOrder: [String: Int] {
        ["Today": 0, "Yesterday": 1, "This week": 2, "This month": 3, "Earlier": 4]
    }
    
    private func refreshNotifications() async {
        // This would typically refresh the notifications
        // For now, we'll just reload the existing ones
        await MainActor.run {
            isLoading = true
        }
        
        // Simulate refresh delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        await MainActor.run {
            isLoading = false
        }
    }

    private func attach() {
        guard listener == nil, let uid = Auth.auth().currentUser?.uid else { return }
        listener = NetworkService.shared.observeNotifications(for: uid) { list in
            notifications = list.sorted { $0.timestamp > $1.timestamp }
        }
    }
    
    // MARK: - Testing
    private func testFollowNotification() {
        print("🔍 TESTING: User tapped test follow notification button")
        NetworkService.shared.createTestFollowNotification { error in
            if let error = error {
                print("🔍 TESTING ERROR: \(error.localizedDescription)")
            } else {
                print("🔍 TESTING: Test follow notification created successfully")
            }
        }
    }
}

struct ActivityRow: View {
    let notification: UserNotification
    
    @State private var post: Post? = nil
    @State private var isLoadingPost = false
    @State private var showProfile = false
    @State private var showPost = false
    
    private var activityMessage: String {
        switch notification.kind {
        case .mention:
            return "mentioned you"
        case .comment:
            return "commented on your post"
        case .like:
            return "liked your post"
        case .tag:
            return "tagged you in a post"
        case .follow:
            return "started following you"
        case .likeComment:
            return "liked your comment"
        case .reply:
            return "replied to your comment"
        case .save:
            return "saved your post"
        }
    }
    
    private var activityIcon: String {
        switch notification.kind {
        case .mention, .tag:
            return "at"
        case .comment, .reply:
            return "message"
        case .like, .likeComment:
            return "heart.fill"
        case .follow:
            return "person.badge.plus"
        case .save:
            return "bookmark"
        }
    }
    
    private var activityColor: Color {
        switch notification.kind {
        case .mention, .tag:
            return .blue
        case .comment, .reply:
            return .green
        case .like, .likeComment:
            return .red
        case .follow:
            return .purple
        case .save:
            return .orange
        }
    }
    
    private var shouldShowPostThumbnail: Bool {
        switch notification.kind {
        case .follow:
            return false
        case .mention, .tag, .like, .comment, .likeComment, .reply, .save:
            return true
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile image
            Button { showProfile = true } label: {
                if let urlString = notification.fromAvatarURL,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                )
                        case .success(let img):
                            img.resizable()
                               .aspectRatio(contentMode: .fill)
                               .frame(width: 44, height: 44)
                               .clipShape(Circle())
                        case .failure:
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.secondary)
                                )
                        @unknown default:
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 44, height: 44)
                        }
                    }
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.secondary)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Activity content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(notification.fromUsername)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(activityMessage)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                        }
                        
                        if notification.kind != .like && notification.kind != .follow && !notification.text.isEmpty {
                            Text(notification.text)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    Text(notification.timeAgo)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Post thumbnail or activity icon
            if notification.kind == .follow {
                // Follow activity - show icon instead of post
                Circle()
                    .fill(activityColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: activityIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(activityColor)
                    )
            } else if let post = post {
                // Post activity - show post thumbnail
                Button { showPost = true } label: {
                    AsyncImage(url: URL(string: post.imageURL)) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                )
                        case .success(let img):
                            img.resizable()
                               .aspectRatio(contentMode: .fill)
                               .frame(width: 44, height: 44)
                               .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                )
                        @unknown default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 44, height: 44)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } else if isLoadingPost {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 44, height: 44)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            } else if shouldShowPostThumbnail {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 44, height: 44)
                    .onAppear(perform: fetchPost)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            NavigationLink(destination: ProfileView(userId: notification.fromUserId),
                           isActive: $showProfile) { EmptyView() }.hidden()
        )
        .background(
            Group {
                if let p = post {
                    NavigationLink(destination: PostDetailView(post: p),
                                   isActive: $showPost) { EmptyView() }.hidden()
                }
            }
        )
    }

    private func fetchPost() {
        guard !isLoadingPost, shouldShowPostThumbnail else { return }
        isLoadingPost = true
        NetworkService.shared.fetchPost(id: notification.postId) { result in
            switch result {
            case .success(let p):
                DispatchQueue.main.async { post = p }
            case .failure:
                if let uid = Auth.auth().currentUser?.uid {
                    NetworkService.shared.deleteNotification(userId: uid,
                                                           notificationId: notification.id) { _ in }
                }
            }
            isLoadingPost = false
        }
    }
}

struct ActivityView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ActivityView()
        }
    }
}
