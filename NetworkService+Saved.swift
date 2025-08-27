import Foundation
import FirebaseFirestore
import FirebaseAuth

extension NetworkService {
    // Local auth error helper since the main one is private
    private static func authError() -> NSError {
        NSError(domain: "Auth", code: -1,
                userInfo: [NSLocalizedDescriptionKey:"Not signed in"])
    }
    
    /// Toggle save / unsave for a post for the current user. The returned Post has `isSaved` toggled
    func toggleSavePost(post: Post, completion: @escaping (Result<Post,Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            return completion(.failure(Self.authError()))
        }
        
        // Use top-level saved_posts collection with compound document ID
        let documentId = "\(uid)_\(post.id)"
        let savedPostRef = db.collection("saved_posts").document(documentId)
        
        db.runTransaction({ (txn, errPtr) -> Any? in
            let doc: DocumentSnapshot
            do {
                doc = try txn.getDocument(savedPostRef)
            } catch {
                errPtr?.pointee = error as NSError
                return nil
            }
            if doc.exists {
                // currently saved → unsave
                txn.deleteDocument(savedPostRef)
            } else {
                // not saved → save
                txn.setData([
                    "userId"   : uid,
                    "postId"   : post.id,
                    "timestamp": Timestamp(date: Date()),
                    "postData" : [
                        "imageURL": post.imageURL,
                        "caption" : post.caption,
                        "userId"  : post.userId
                    ]
                ], forDocument: savedPostRef)
            }
            return nil
        }) { _, error in
            if let error { completion(.failure(error)); return }
            var updated = post
            updated.isSaved.toggle()
            completion(.success(updated))
        }
    }

    /// Fetch all saved posts for current user
    func fetchSavedPosts(completion: @escaping (Result<[Post],Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            return completion(.failure(Self.authError()))
        }
        
        db.collection("saved_posts")
            .whereField("userId", isEqualTo: uid)
            .order(by: "timestamp", descending: true)
            .getDocuments { snap, err in
                if let err { completion(.failure(err)); return }
                guard let snap else { completion(.success([])); return }
                
                let savedDocs = snap.documents
                if savedDocs.isEmpty { completion(.success([])); return }
                
                var posts: [Post] = []
                let group = DispatchGroup()
                var fetchErr: Error?
                
                for savedDoc in savedDocs {
                    group.enter()
                    let postId = savedDoc.data()["postId"] as? String ?? ""
                    
                    self.db.collection("posts").document(postId).getDocument { doc, err in
                        defer { group.leave() }
                        if let err { fetchErr = err; return }
                        guard let doc, doc.exists,
                              let d = doc.data(),
                              let uid = d["userId"] as? String,
                              let imgURL = d["imageURL"] as? String,
                              let caption = d["caption"] as? String,
                              let ts = d["timestamp"] as? Timestamp,
                              let likes = d["likes"] as? Int
                        else { return }
                        let likedBy = d["likedBy"] as? [String] ?? []
                        let me = Auth.auth().currentUser?.uid
                        let liked = me.map { likedBy.contains($0) } ?? (d["isLiked"] as? Bool ?? false)
                        var post = Post(
                            id: doc.documentID,
                            userId: uid,
                            imageURL: imgURL,
                            caption: caption,
                            timestamp: ts.dateValue(),
                            likes: likes,
                            isLiked: liked,
                            latitude: d["latitude"] as? Double,
                            longitude: d["longitude"] as? Double,
                            temp: d["temp"] as? Double,
                            weatherIcon: d["weatherIcon"] as? String,
                            outfitItems: NetworkService.parseOutfitItems(d["scanResults"]),
                            outfitTags: NetworkService.parseOutfitTags(d["outfitTags"]),
                            hashtags: d["hashtags"] as? [String] ?? []
                        )
                        post.isSaved = true
                        posts.append(post)
                    }
                }
                
                group.notify(queue: .main) {
                    if let e = fetchErr { completion(.failure(e)); return }
                    completion(.success(posts.sorted { $0.timestamp > $1.timestamp }))
                }
            }
    }

    /// Check if a single post is saved by current user
    func isPostSaved(postId: String, completion: @escaping (Result<Bool,Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            return completion(.failure(Self.authError()))
        }
        
        let documentId = "\(uid)_\(postId)"
        db.collection("saved_posts").document(documentId).getDocument { doc, err in
            if let err { completion(.failure(err)); return }
            completion(.success(doc?.exists == true))
        }
    }
    
    /// Check save states for multiple posts at once (more efficient)
    func checkSaveStates(for postIds: [String], completion: @escaping (Result<[String: Bool], Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            return completion(.failure(Self.authError()))
        }
        
        if postIds.isEmpty {
            completion(.success([:]))
            return
        }
        
        let group = DispatchGroup()
        var results: [String: Bool] = [:]
        var fetchError: Error?
        
        for postId in postIds {
            group.enter()
            let documentId = "\(uid)_\(postId)"
            db.collection("saved_posts").document(documentId).getDocument { doc, err in
                defer { group.leave() }
                if let err { fetchError = err; return }
                results[postId] = doc?.exists == true
            }
        }
        
        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
            } else {
                completion(.success(results))
            }
        }
    }
} 