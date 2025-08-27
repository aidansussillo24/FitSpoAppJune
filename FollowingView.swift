// FollowingView.swift

import SwiftUI
import FirebaseFirestore

/// Same lightweight model as FollowersView.
private struct ProfileItem: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: String?
}

struct FollowingView: View {
    let userId: String

    @State private var following: [ProfileItem] = []
    @State private var filteredFollowing: [ProfileItem] = []
    @State private var isLoading    = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar - only show when we have data and not loading
            if !following.isEmpty && !isLoading {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16, weight: .medium))
                        
                        TextField("Search following", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 16))
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            
            // Main content area
            if let error = errorMessage {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Error loading following")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
            } else if following.isEmpty && !isLoading {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Not following anyone yet")
                            .font(.headline)
                        Text("When you follow people, they'll appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
            } else if filteredFollowing.isEmpty && !searchText.isEmpty && !isLoading {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No results found")
                            .font(.headline)
                        Text("Try searching with a different name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
            } else if !filteredFollowing.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFollowing) { user in
                            NavigationLink(destination: ProfileView(userId: user.id)) {
                                HStack(spacing: 16) {
                                    // Profile Image
                                    if let urlString = user.avatarURL,
                                       let url = URL(string: urlString) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .empty:
                                                Circle()
                                                    .fill(Color(.systemGray5))
                                                    .frame(width: 50, height: 50)
                                                    .overlay(
                                                        ProgressView()
                                                            .scaleEffect(0.8)
                                                    )
                                            case .success(let img):
                                                img.resizable()
                                                   .aspectRatio(contentMode: .fill)
                                                   .frame(width: 50, height: 50)
                                                   .clipShape(Circle())
                                            case .failure:
                                                Circle()
                                                    .fill(Color(.systemGray5))
                                                    .frame(width: 50, height: 50)
                                                    .overlay(
                                                        Image(systemName: "person.fill")
                                                            .foregroundColor(.secondary)
                                                    )
                                            @unknown default:
                                                Circle()
                                                    .fill(Color(.systemGray5))
                                                    .frame(width: 50, height: 50)
                                            }
                                        }
                                    } else {
                                        Circle()
                                            .fill(Color(.systemGray5))
                                            .frame(width: 50, height: 50)
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.secondary)
                                            )
                                    }

                                    // User Info
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    // Chevron
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color(.systemBackground))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if user.id != filteredFollowing.last?.id {
                                Divider()
                                    .padding(.leading, 86)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Following")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadList(from: "following")
        }
        .task {
            await loadList(from: "following")
        }
        .onChange(of: searchText) { _ in
            filterFollowing()
        }
    }
    
    private func filterFollowing() {
        if searchText.isEmpty {
            filteredFollowing = following
        } else {
            filteredFollowing = following.filter { user in
                user.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func loadList(from collectionName: String) async {
        isLoading     = true
        errorMessage  = nil
        following     = []
        filteredFollowing = []

        let db = Firestore.firestore()
        do {
            let snap = try await db
                .collection("users")
                .document(userId)
                .collection(collectionName)
                .getDocuments()
            let ids = snap.documents.map(\.documentID)

            var loaded: [ProfileItem] = []
            for id in ids {
                let doc = try await db
                    .collection("users")
                    .document(id)
                    .getDocument()
                guard let data = doc.data() else { continue }
                let name   = data["displayName"] as? String ?? "No Name"
                let avatar = data["avatarURL"]   as? String
                loaded.append(.init(id: id, displayName: name, avatarURL: avatar))
            }

            following = loaded.sorted { $0.displayName < $1.displayName }
            filteredFollowing = following
        }
        catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct FollowingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FollowingView(userId: "dummyUserID")
        }
    }
}
