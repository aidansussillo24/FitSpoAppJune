// FollowersView.swift

import SwiftUI
import FirebaseFirestore

/// Simple struct for each user in the list.
private struct ProfileItem: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: String?
}

struct FollowersView: View {
    let userId: String

    @State private var followers: [ProfileItem] = []
    @State private var filteredFollowers: [ProfileItem] = []
    @State private var isLoading   = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar - only show when we have data and not loading
            if !followers.isEmpty && !isLoading {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16, weight: .medium))
                        
                        TextField("Search followers", text: $searchText)
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
                        Text("Error loading followers")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
            } else if followers.isEmpty && !isLoading {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No followers yet")
                            .font(.headline)
                        Text("When people follow this profile, they'll appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
            } else if filteredFollowers.isEmpty && !searchText.isEmpty && !isLoading {
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
            } else if !filteredFollowers.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFollowers) { user in
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
                            
                            if user.id != filteredFollowers.last?.id {
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
        .navigationTitle("Followers")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadList(from: "followers")
        }
        .task {
            await loadList(from: "followers")
        }
        .onChange(of: searchText) { _ in
            filterFollowers()
        }
    }
    
    private func filterFollowers() {
        if searchText.isEmpty {
            filteredFollowers = followers
        } else {
            filteredFollowers = followers.filter { user in
                user.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func loadList(from collectionName: String) async {
        isLoading     = true
        errorMessage  = nil
        followers     = []
        filteredFollowers = []

        let db = Firestore.firestore()
        do {
            // 1) get the IDs in the sub-collection
            let snap = try await db
                .collection("users")
                .document(userId)
                .collection(collectionName)
                .getDocuments()
            let ids = snap.documents.map(\.documentID)

            // 2) fetch each user profile doc
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

            // 3) sort (alphabetical)
            followers = loaded.sorted { $0.displayName < $1.displayName }
            filteredFollowers = followers
        }
        catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct FollowersView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FollowersView(userId: "dummyUserID")
        }
    }
}
