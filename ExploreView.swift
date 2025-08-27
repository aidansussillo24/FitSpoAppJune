//
//  ExploreView.swift
//  FitSpo
//
//  Phase 2.3 – hashtag filtering + full account‑list mode
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ExploreView: View {

    // ────────── Layout constants ──────────
    private let cardWidth: CGFloat = 280
    private var imageHeight: CGFloat { cardWidth * 5 / 4 }  // 4 : 5 aspect
    private var cardHeight: CGFloat { imageHeight + 48 + 36 + 20 } // header + footer + extra padding

    private let spacing: CGFloat = 2
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 120), spacing: spacing)] }

    // ────────── State ──────────
    @State private var searchText = ""
    @State private var accountHits: [UserLite] = []
    @State private var isSearchingAccounts = false
    @State private var showResults = false
    @State private var selectedUserId: String? = nil

    @State private var hashtagSuggestions: [String] = []
    @State private var hashtagCounts: [String: Int] = [:]
    @State private var isSearchingHashtags = false
    @State private var showSuggestions = false

    // Content sections
    @State private var topPosts: [Post]        = []
    @State private var newYorkPosts: [Post]    = []
    @State private var losAngelesPosts: [Post] = []
    @State private var sanFranciscoPosts: [Post] = []
    @State private var miamiPosts: [Post]      = []
    @State private var chicagoPosts: [Post]    = []

    @State private var isLoading = false

    private var isAccountMode: Bool {
        !searchText.isEmpty && searchText.first != "#"
    }

    // MARK: - Content Section (horizontal scrolling cards)
    private func contentSection(title: String, posts: [Post]) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // Section Title
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Horizontal list of post cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(posts) { post in
                                                 PostCardView(post: post, fixedImageHeight: imageHeight) {
                             Task { await toggleLike(post) }
                         }
                        .frame(width: cardWidth, height: cardHeight)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: cardHeight)
            .padding(.bottom, 32) // extra space after section
        }
    }

    // ────────── Body ──────────
    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    // Normal Explore content
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            contentSection(title: "Top posts",      posts: topPosts)
                            contentSection(title: "New York",       posts: newYorkPosts)
                            contentSection(title: "Los Angeles",    posts: losAngelesPosts)
                            contentSection(title: "San Francisco",  posts: sanFranciscoPosts)
                            contentSection(title: "Miami",          posts: miamiPosts)
                            contentSection(title: "Chicago",        posts: chicagoPosts)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    }
                } else {
                    // Search takes over the entire screen
                    searchContent
                }
            }
            .navigationTitle("Explore")
            .searchable(text: $searchText, prompt: "Search accounts or #tags")
            .onSubmit(of: .search) {
                if !searchText.isEmpty {
                    showResults = true
                    showSuggestions = false
                }
            }
            .onChange(of: searchText, perform: handleSearchChange)
            .refreshable { await loadContent() }
            .task { await loadContent() }
            .navigationDestination(isPresented: $showResults) {
                SearchResultsView(query: searchText)
            }
            .navigationDestination(item: $selectedUserId) { userId in
                ProfileView(userId: userId)
            }
            .onChange(of: selectedUserId) { newValue in
                if newValue == nil && !searchText.isEmpty {
                    showSuggestions = true
                    Task { await fetchSuggestions() }
                }
            }
            .onAppear {
                if !searchText.isEmpty && selectedUserId == nil {
                    showSuggestions = true
                    Task { await fetchSuggestions() }
                }
            }
        }
    }

    // ────────── Search callbacks ──────────
    private func handleSearchChange(_ q: String) {
        showSuggestions = !q.isEmpty
        Task { await fetchSuggestions() }
    }

    private func fetchSuggestions() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            accountHits = []
            hashtagSuggestions = []
            hashtagCounts = [:]
            return
        }
        if trimmed.first == "#" {
            // Only hashtag suggestions
            isSearchingHashtags = true
            defer { isSearchingHashtags = false }
            let prefix = String(trimmed.dropFirst())
            do {
                hashtagSuggestions = try await NetworkService.shared.suggestHashtags(prefix: prefix)
                // Get post counts for hashtags
                hashtagCounts = [:]
                for tag in hashtagSuggestions {
                    do {
                        let posts = try await NetworkService.shared.searchPosts(hashtag: tag, limit: 1)
                        hashtagCounts[tag] = posts.count
                    } catch {
                        hashtagCounts[tag] = 0
                    }
                }
            } catch {
                hashtagSuggestions = []
                hashtagCounts = [:]
            }
            accountHits = []
        } else {
            // Both accounts and hashtags
            async let users: Void = {
                isSearchingAccounts = true
                defer { isSearchingAccounts = false }
                do {
                    accountHits = try await NetworkService.shared.searchUsers(prefix: trimmed)
                } catch {
                    accountHits = []
                }
            }()
            async let hashtags: Void = {
                isSearchingHashtags = true
                defer { isSearchingHashtags = false }
                do {
                    hashtagSuggestions = try await NetworkService.shared.suggestHashtags(prefix: trimmed)
                    // Get post counts for hashtags
                    hashtagCounts = [:]
                    for tag in hashtagSuggestions {
                        do {
                            let posts = try await NetworkService.shared.searchPosts(hashtag: tag, limit: 1)
                            hashtagCounts[tag] = posts.count
                        } catch {
                            hashtagCounts[tag] = 0
                        }
                    }
                } catch {
                    hashtagSuggestions = []
                    hashtagCounts = [:]
                }
            }()
            _ = await (users, hashtags)
        }
    }

    // ────────── UI pieces ──────────
    private var searchContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 8) // Spacing below search bar

            if isSearchingAccounts || isSearchingHashtags {
                VStack {
                    Spacer()
                    ProgressView().padding()
                    Text("Searching…").foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if searchText.first == "#" {
                            if hashtagSuggestions.isEmpty {
                                emptyState("No hashtags found")
                            } else {
                                hashtagButtons(hashtagSuggestions)
                            }
                        } else {
                            if accountHits.isEmpty && hashtagSuggestions.isEmpty {
                                emptyState("No results found")
                            } else {
                                accountButtons(accountHits)
                                hashtagButtons(hashtagSuggestions)
                            }
                        }
                    }
                    .padding(.bottom, 80)
                }
            }
        }
    }

    // MARK: - Helper UI builders
    @ViewBuilder private func emptyState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder private func accountButtons(_ users: [UserLite]) -> some View {
        VStack(spacing: 0) {
            if !users.isEmpty {
                HStack {
                    Text("Accounts")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                ForEach(users) { u in
                    Button {
                        selectedUserId = u.id
                        showSuggestions = false
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: u.avatarURL)) { phase in
                                if let img = phase.image { 
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else { 
                                    Color.gray.opacity(0.3) 
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.displayName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("@\(u.displayName.lowercased().replacingOccurrences(of: " ", with: ""))")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)
                    
                    if u.id != users.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
        }
    }

    @ViewBuilder private func hashtagButtons(_ tags: [String]) -> some View {
        VStack(spacing: 0) {
            if !tags.isEmpty {
                HStack {
                    Text("Hashtags")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                ForEach(tags, id: \.self) { tag in
                    Button {
                        searchText = "#" + tag
                        showResults = true
                        showSuggestions = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "number")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.blue)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#\(tag)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                if let count = hashtagCounts[tag], count > 0 {
                                    Text("\(count) \(count == 1 ? "post" : "posts")")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)
                    
                    if tag != tags.last {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    // MARK: - Content Loading
    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        await loadTopPosts()
        newYorkPosts      = await loadCityPosts(city: "New York")
        losAngelesPosts   = await loadCityPosts(city: "Los Angeles")
        sanFranciscoPosts = await loadCityPosts(city: "San Francisco")
        miamiPosts        = await loadCityPosts(city: "Miami")
        chicagoPosts      = await loadCityPosts(city: "Chicago")
        
        // Update save states for all loaded posts
        updateSaveStates()
    }

    private func loadTopPosts() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NetworkService.shared.fetchPostsPage(pageSize: 10, after: nil) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let (posts, _)):
                        let recent = posts.filter { $0.timestamp > yesterday }
                        topPosts = recent.sorted { $0.likes > $1.likes }
                                         .prefix(10)
                                         .map { $0 }
                    case .failure(let error):
                        print("Failed to load top posts: \(error)")
                        topPosts = []
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func loadCityPosts(city: String) async -> [Post] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[Post], Never>) in
            NetworkService.shared.fetchPostsPage(pageSize: 8, after: nil) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let (allPosts, _)):
                        continuation.resume(returning: Array(allPosts.prefix(8)))
                    case .failure(let error):
                        print("Failed to load \(city) posts: \(error)")
                        continuation.resume(returning: [])
                    }
                }
            }
        }
    }

    private func toggleLike(_ post: Post) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NetworkService.shared.toggleLike(post: post) { result in
                DispatchQueue.main.async {
                    if case .success(let updated) = result {
                        updatePostInArrays(updated)
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func updatePostInArrays(_ updated: Post) {
        func replace(in array: inout [Post]) {
            if let idx = array.firstIndex(where: { $0.id == updated.id }) {
                array[idx] = updated
            }
        }
        replace(in: &topPosts)
        replace(in: &newYorkPosts)
        replace(in: &losAngelesPosts)
        replace(in: &sanFranciscoPosts)
        replace(in: &miamiPosts)
        replace(in: &chicagoPosts)
    }
    
    private func updateSaveStates() {
        // Collect all post IDs from all arrays
        let allPostIds = topPosts.map { $0.id } +
                        newYorkPosts.map { $0.id } +
                        losAngelesPosts.map { $0.id } +
                        sanFranciscoPosts.map { $0.id } +
                        miamiPosts.map { $0.id } +
                        chicagoPosts.map { $0.id }
        
        NetworkService.shared.checkSaveStates(for: allPostIds) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let saveStates):
                    func updateArray(_ array: inout [Post]) {
                        for (index, post) in array.enumerated() {
                            if let isSaved = saveStates[post.id] {
                                var updatedPost = post
                                updatedPost.isSaved = isSaved
                                array[index] = updatedPost
                            }
                        }
                    }
                    updateArray(&topPosts)
                    updateArray(&newYorkPosts)
                    updateArray(&losAngelesPosts)
                    updateArray(&sanFranciscoPosts)
                    updateArray(&miamiPosts)
                    updateArray(&chicagoPosts)
                case .failure(let error):
                    print("Error updating save states in ExploreView: \(error.localizedDescription)")
                }
            }
        }
    }
}

// ────────── Grid image tile (unchanged) ──────────
private struct ImageTile: View {
    let url: String
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .empty:   Color.gray.opacity(0.12)
                case .success(let img): img.resizable().scaledToFill()
                case .failure: Color.gray.opacity(0.12)
                @unknown default: Color.gray.opacity(0.12)
                }
            }
            .frame(width: side, height: side)
            .clipped()
            .cornerRadius(8)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

//  End of file
