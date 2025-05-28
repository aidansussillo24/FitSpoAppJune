// HomeView.swift

import SwiftUI

struct HomeView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ─── Header ─────────────────────────────────────
                    ZStack {
                        Text("FitSpo")
                            .font(.largeTitle)
                            .fontWeight(.black)
                        HStack {
                            Spacer()
                            Button {
                                // toggle layout if you want
                            } label: {
                                Image(systemName: "rectangle.grid.2x2")
                                    .font(.title2)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // ─── Featured 2×2 ───────────────────────────────
                    LazyVGrid(
                        columns: [ GridItem(.flexible(), spacing: 8),
                                   GridItem(.flexible(), spacing: 8) ],
                        spacing: 8
                    ) {
                        ForEach(posts.prefix(4), id: \.id) { post in
                            PostCardView(post: post) { toggleLike(post) }
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ─── Standard 3-column ──────────────────────────
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                        spacing: 8
                    ) {
                        ForEach(posts.dropFirst(4), id: \.id) { post in
                            PostCardView(post: post) { toggleLike(post) }
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .navigationBarHidden(true)
            .onAppear(perform: loadPosts)
        }
    }

    // MARK: Networking

    private func loadPosts() {
        guard !isLoading else { return }
        isLoading = true

        NetworkService.shared.fetchPosts { result in
            DispatchQueue.main.async {
                isLoading = false
                if case .success(let all) = result {
                    posts = all
                } else if case .failure(let err) = result {
                    print("❌ fetch failed:", err)
                }
            }
        }
    }

    private func toggleLike(_ post: Post) {
        NetworkService.shared.toggleLike(post: post) { result in
            DispatchQueue.main.async {
                if case .success(let updated) = result,
                   let idx = posts.firstIndex(where: { $0.id == updated.id }) {
                    posts[idx] = updated
                }
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View { HomeView() }
}
