import SwiftUI

struct PostCardView: View {
    let post: Post
    let onLike: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ─── Main Image ─────────────────────────────
            AsyncImage(url: URL(string: post.imageURL)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color.gray.opacity(0.2)
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
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
            .clipped()

            // ─── Footer: Avatar, Username & Likes ─────
            HStack(spacing: 8) {
                // Placeholder avatar
                Image("profile_placeholder")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())

                // Username
                Text(post.userId)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Like button + count
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        Text("\(post.likes)")
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(8)
            .background(Color.white)
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#if DEBUG
struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        let sample = Post(
            id:        "1",
            userId:    "oliviaw",
            imageURL:  "https://via.placeholder.com/600",
            caption:   "",
            timestamp: Date(),
            likes:     100,
            isLiked:   false,
            latitude:  nil,
            longitude: nil
        )
        PostCardView(post: sample, onLike: {})
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
