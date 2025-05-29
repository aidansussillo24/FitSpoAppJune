import SwiftUI

struct HomeView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false

    // Split into two columns by alternating
    private var leftColumn:  [Post] { posts.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element } }
    private var rightColumn: [Post] { posts.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map { $0.element } }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header

                    // ─── Masonry Grid ────────────────────
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 8) {
                            ForEach(leftColumn) { post in
                                PostCardView(post: post) {
                                    toggleLike(post)
                                }
                            }
                        }
                        VStack(spacing: 8) {
                            ForEach(rightColumn) { post in
                                PostCardView(post: post) {
                                    toggleLike(post)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationBarHidden(true)
            .onAppear(perform: loadPosts)
        }
    }

    private var header: some View {
        ZStack {
            Text("FitSpo")
                .font(.largeTitle)
                .fontWeight(.black)
            HStack {
                Spacer()
                Button {
                    // optional layout toggle
                } label: {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.title2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func loadPosts() {
        guard !isLoading else { return }
        isLoading = true
        NetworkService.shared.fetchPosts { result in
            DispatchQueue.main.async {
                isLoading = false
                if case .success(let all) = result {
                    posts = all
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
    static var previews: some View {
        HomeView()
    }
}
