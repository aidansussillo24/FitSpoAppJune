//
//  PostDetailView.swift
//  FitSpo
//
//  Displays one post (image, likes, comments) + cached outfit scan.
//
//  Updated 2025‑06‑18:
//  • State `outfitItems` no longer initialises to an empty array
//    – it’s filled with the cached items coming from Firestore.
//  • `init(post:)` seed updated field.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import UIKit        // ZoomableAsyncImage

// ─────────────────────────────────────────────────────────────
struct PostDetailView: View {

    // MARK: – injected model
    let post: Post
    @Environment(\.dismiss) private var dismiss

    // MARK: – author info
    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    // MARK: – location chip
    @State private var locationName = ""

    // MARK: – like state
    @State private var isLiked: Bool
    @State private var likesCount: Int
    @State private var showHeartBurst = false

    // MARK: – comments state
    @State private var commentCount: Int = 0
    @State private var showComments = false

    // MARK: – share / chat state
    @State private var showShareSheet = false
    @State private var shareChat: Chat?
    @State private var navigateToChat = false

    // MARK: – delete UX
    @State private var isDeleting        = false
    @State private var showDeleteConfirm = false

    // MARK: – outfit‑scan sheet
    @State private var isScanning      = false
    @State private var outfitItems     : [OutfitItem]
    @State private var showOutfitSheet = false

    // MARK: – misc
    @State private var postListener: ListenerRegistration?
    @State private var imgRatio: CGFloat? = nil
    @State private var postTags: [UserTag] = []

    // MARK: – init
    init(post: Post) {
        self.post = post
        _isLiked       = State(initialValue: post.isLiked)
        _likesCount    = State(initialValue: post.likes)
        _outfitItems   = State(initialValue: post.outfitItems ?? [])
    }

    // =========================================================
    // MARK: body
    // =========================================================
    var body: some View {
        ZStack(alignment: .bottom) {

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    postImage
                    actionRow
                    captionRow
                    timestampRow
                    Spacer(minLength: 32)
                }
                .padding(.top)
            }

            if showComments {
                CommentsOverlay(
                    post: post,
                    isPresented: $showComments,
                    onCommentCountChange: { commentCount = $0 }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: showComments)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarDeleteButton }
        .alert("Delete Post?", isPresented: $showDeleteConfirm,
               actions: deleteAlertButtons)
        .overlay { if isDeleting { deletingOverlay } }
        .sheet(isPresented: $showShareSheet)  { shareSheet }
        .sheet(isPresented: $showOutfitSheet) { outfitSheet }
        .background { chatNavigationLink }
        .onAppear   { attachListenersAndFetch() }
        .onDisappear{ postListener?.remove() }
    }

    // MARK: ----------------------------------------------------
    // MARK: sub‑views
    // MARK: ----------------------------------------------------

    // HEADER
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                avatarView
            }

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
    }

    // MAIN IMAGE
    private var postImage: some View {
        GeometryReader { geo in
            if let url = URL(string: post.imageURL) {
                ZoomableAsyncImage(url: url, aspectRatio: $imgRatio)
                    .frame(width: geo.size.width,
                           height: (imgRatio ?? 1) * geo.size.width)
                    .clipped()
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { handleDoubleTapLike() }
                    )
                    .overlay(HeartBurstView(trigger: $showHeartBurst))
                    .overlay(
                        ForEach(postTags) { tag in
                            NavigationLink(
                                destination: ProfileView(userId: tag.id)
                            ) {
                                Text(tag.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .padding(6)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .position(
                                x: tag.xNorm * geo.size.width,
                                y: tag.yNorm * geo.size.width * (imgRatio ?? 1)
                            )
                        }
                    )
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .frame(height: UIScreen.main.bounds.width * (imgRatio ?? 1))
    }

    // ACTION ROW  (includes hanger button)
    private var actionRow: some View {
        HStack(spacing: 24) {
            likeButton
            Text("\(likesCount)")
                .font(.subheadline.weight(.semibold))

            commentButton
            Text("\(commentCount)")
                .font(.subheadline.weight(.semibold))

            // hanger → opens sheet and (optionally) triggers scan
            Button {
                showOutfitSheet = true
                if outfitItems.isEmpty { scanOutfit() }
            } label: {
                Image(systemName: "hanger")
                    .font(.title2)
            }
            .disabled(isScanning)

            shareButton
            Spacer()
        }
        .padding(.horizontal)
    }

    private var captionRow: some View {
        HStack(alignment: .top, spacing: 4) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                Text(isLoadingAuthor ? "Loading…" : authorName)
                    .fontWeight(.semibold)
            }
            Text(post.caption)
        }
        .padding(.horizontal)
    }

    private var timestampRow: some View {
        Text(post.timestamp, style: .time)
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.horizontal)
    }

    @ViewBuilder private var avatarView: some View {
        Group {
            if let url = URL(string: authorAvatarURL),
               !authorAvatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:   ProgressView()
                    case .success: phase.image!.resizable().scaledToFill()
                    default:       Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    // MARK: – buttons
    private var likeButton: some View {
        Button(action: toggleLike) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.title2)
                .foregroundColor(isLiked ? .red : .primary)
        }
    }

    private var commentButton: some View {
        Button { showComments = true } label: {
            Image(systemName: "bubble.right").font(.title2)
        }
    }

    private var shareButton: some View {
        Button { showShareSheet = true } label: {
            Image(systemName: "paperplane").font(.title2)
        }
    }

    // MARK: ----------------------------------------------------
    // MARK: post actions
    // MARK: ----------------------------------------------------

    private func toggleLike() {
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        NetworkService.shared.toggleLike(post: post) { _ in }
    }

    private func handleDoubleTapLike() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        showHeartBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showHeartBurst = false
        }
        if !isLiked { toggleLike() }
    }

    private func performDelete() {
        isDeleting = true
        NetworkService.shared.deletePost(id: post.id) { res in
            DispatchQueue.main.async {
                isDeleting = false
                if case .success = res { dismiss() }
            }
        }
    }

    private func sharePost(to userId: String) {
        guard let me = Auth.auth().currentUser?.uid else { return }
        let pair = [me, userId].sorted()
        NetworkService.shared.createChat(participants: pair) { res in
            switch res {
            case .success(let chat):
                NetworkService.shared.sendPost(chatId: chat.id, postId: post.id) { _ in }
                DispatchQueue.main.async {
                    shareChat = chat
                    navigateToChat = true
                }
            case .failure(let err):
                print("Chat creation error:", err)
            }
        }
    }

    // =========================================================
    // MARK: Outfit‑AI scan helper
    // =========================================================
    @MainActor
    private func scanOutfit() {
        guard !isScanning else { return }
        isScanning  = true
        outfitItems = []

        Task {
            defer { isScanning = false }
            do {
                let start = try await NetworkService.scanOutfit(
                    postId:   post.id,
                    imageURL: post.imageURL
                )
                let fin = try await NetworkService.waitForReplicate(prediction: start)
                let objs = fin.output?.json_data.objects ?? []
                outfitItems = objs.enumerated().map { idx, det in
                    OutfitItem(
                        id: "d\(idx)",
                        label: det.name,
                        brand: "",
                        shopURL: "https://www.google.com/search?q="
                               + det.name.addingPercentEncoding(
                                   withAllowedCharacters: .urlQueryAllowed
                                 )!
                    )
                }
            } catch {
                print("Outfit scan failed:", error)
                outfitItems = []
            }
        }
    }

    // MARK: ----------------------------------------------------
    // MARK: toolbar & sheets
    // MARK: ----------------------------------------------------

    private var toolbarDeleteButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if post.userId == Auth.auth().currentUser?.uid {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
    }

    @ViewBuilder private func deleteAlertButtons() -> some View {
        Button("Delete", role: .destructive, action: performDelete)
        Button("Cancel",  role: .cancel) { }
    }

    private var deletingOverlay: some View {
        ProgressView("Deleting…")
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var shareSheet: some View {
        ShareToUserView { uid in
            showShareSheet = false
            sharePost(to: uid)
        }
    }

    private var outfitSheet: some View {
        OutfitItemSheet(
            items: outfitItems,
            isScanning: isScanning,
            isPresented: $showOutfitSheet
        )
        .presentationDetents([.fraction(0.45), .large])
    }

    private var chatNavigationLink: some View {
        Group {
            if let chat = shareChat {
                NavigationLink(destination: ChatDetailView(chat: chat),
                               isActive: $navigateToChat) { EmptyView() }
                    .hidden()
            }
        }
    }

    // MARK: ----------------------------------------------------
    // MARK: Firestore & helpers
    // MARK: ----------------------------------------------------

    private func attachListenersAndFetch() {
        attachPostListener()
        fetchAuthor()
        fetchLocationName()
        fetchCommentCount()
        fetchTags()
    }

    private func attachPostListener() {
        guard postListener == nil else { return }
        Firestore.firestore().collection("posts").document(post.id)
            .addSnapshotListener { snap, _ in
                guard let d = snap?.data() else { return }
                likesCount   = d["likes"] as? Int ?? likesCount
                commentCount = d["commentsCount"] as? Int ?? commentCount
                if let likedBy = d["likedBy"] as? [String],
                   let uid = Auth.auth().currentUser?.uid {
                    isLiked = likedBy.contains(uid)
                }
            }
    }

    private func fetchAuthor() {
        Firestore.firestore().collection("users")
            .document(post.userId)
            .getDocument { snap, _ in
                isLoadingAuthor = false
                let d = snap?.data() ?? [:]
                authorName      = d["displayName"] as? String ?? "Unknown"
                authorAvatarURL = d["avatarURL"]   as? String ?? ""
            }
    }

    private func fetchLocationName() {
        guard let lat = post.latitude, let lon = post.longitude else { return }
        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: lat, longitude: lon)
        ) { places, _ in
            guard let p = places?.first else { return }
            var parts = [String]()
            if let city   = p.locality           { parts.append(city) }
            if let region = p.administrativeArea { parts.append(region) }
            if parts.isEmpty, let country = p.country { parts.append(country) }
            locationName = parts.joined(separator: ", ")
        }
    }

    private func fetchCommentCount() {
        NetworkService.shared.fetchComments(for: post.id) { res in
            if case .success(let list) = res { commentCount = list.count }
        }
    }

    private func fetchTags() {
        NetworkService.shared.fetchTags(for: post.id) { res in
            if case .success(let list) = res { postTags = list }
        }
    }
}
//  End of PostDetailView.swift
