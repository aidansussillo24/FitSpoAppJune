//
//  NetworkService.swift
//  FitSpo
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Network                                   // for reachability

/// A singleton to manage all Firebase calls.
final class NetworkService {
    static let shared = NetworkService()

    /// Live reachability flag (used by ExploreView.reload)
    public static private(set) var isOnline: Bool = true

    // Firestore & Storage handles — visible to every extension file
    let db      = Firestore.firestore()
    let storage = Storage.storage().reference()

    // ------------------------------------------------------------------
    // MARK:  Init – start a tiny NWPathMonitor so we always know online / offline
    // ------------------------------------------------------------------
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            Self.isOnline = (path.status == .satisfied)
        }
        monitor.start(queue: .global(qos: .background))
    }

    // ==================================================================
    // MARK:  User profile (adds username_lc)
    // ==================================================================
    func createUserProfile(
        userId: String,
        data: [String : Any],
        completion: @escaping (Result<Void,Error>) -> Void
    ) {
        var payload = data
        if payload["username_lc"] == nil,
           let dn = payload["displayName"] as? String {
            payload["username_lc"] = dn.lowercased()
        }

        db.collection("users").document(userId).setData(payload) { err in
            if let err { completion(.failure(err)) }
            else       { completion(.success(()))  }
        }
    }

    // ==================================================================
    // MARK:  Upload post (stores hashtags[])
    // ==================================================================
    func uploadPost(
        image: UIImage,
        caption: String,
        latitude: Double?,
        longitude: Double?,
        completion: @escaping (Result<Void,Error>) -> Void
    ) {
        guard let me   = Auth.auth().currentUser else {
            return completion(.failure(Self.authError()))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            return completion(.failure(Self.imageError()))
        }

        let imgID = UUID().uuidString
        let ref   = storage.child("post_images/\(imgID).jpg")

        ref.putData(jpeg, metadata: nil) { [weak self] _, err in
            if let err { return completion(.failure(err)) }

            ref.downloadURL { url, err in
                if let err { return completion(.failure(err)) }
                guard let url else {
                    return completion(.failure(Self.storageURLError()))
                }

                var post: [String:Any] = [
                    "userId"   : me.uid,
                    "imageURL" : url.absoluteString,
                    "caption"  : caption,
                    "timestamp": Timestamp(date: Date()),
                    "likes"    : 0,
                    "isLiked"  : false,
                    "hashtags" : Self.extractHashtags(from: caption)
                ]
                if let latitude  { post["latitude"]  = latitude  }
                if let longitude { post["longitude"] = longitude }

                self?.db.collection("posts").addDocument(data: post) { err in
                    if let err { completion(.failure(err)) }
                    else       { completion(.success(()))  }
                }
            }
        }
    }

    // ==================================================================
    // MARK:  Fetch posts (home feed)
    // ==================================================================
    func fetchPosts(
        completion: @escaping (Result<[Post],Error>) -> Void
    ) {
        db.collection("posts")
          .order(by: "timestamp", descending: true)
          .getDocuments { snap, err in
              if let err { return completion(.failure(err)) }
              let posts = snap?.documents.compactMap(Self.decodePost) ?? []
              completion(.success(posts))
          }
    }

    // ==================================================================
    // MARK:  Toggle like
    // ==================================================================
    func toggleLike(post: Post,
                    completion: @escaping (Result<Post,Error>) -> Void) {
        let ref      = db.collection("posts").document(post.id)
        let delta    = post.isLiked ? -1 : 1
        let newLikes = post.likes + delta
        let newLiked = !post.isLiked

        ref.updateData([
            "likes"  : newLikes,
            "isLiked": newLiked
        ]) { err in
            if let err { completion(.failure(err)); return }
            var updated = post
            updated.likes   = newLikes
            updated.isLiked = newLiked
            completion(.success(updated))
        }
    }

    // ==================================================================
    // MARK:  Delete post (doc + Storage asset)
    // ==================================================================
    func deletePost(
        id: String,
        completion: @escaping (Result<Void,Error>) -> Void
    ) {
        let ref = db.collection("posts").document(id)
        ref.getDocument { snap, err in
            if let err { return completion(.failure(err)) }

            guard
                let d   = snap?.data(),
                let url = URL(string: d["imageURL"] as? String ?? "")
            else {
                ref.delete { err in
                    err == nil ? completion(.success(()))
                               : completion(.failure(err!))
                }
                return
            }

            Storage.storage()
                .reference(withPath: url.path.dropFirst().description)
                .delete { _ in
                    ref.delete { err in
                        err == nil ? completion(.success(()))
                                   : completion(.failure(err!))
                    }
                }
        }
    }

    // ==================================================================
    // MARK:  Follow / unfollow / counts
    // ==================================================================
    func follow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(Self.authError())
        }
        let batch = db.batch()
        let follower = db.collection("users").document(userId)
                         .collection("followers").document(me)
        let following = db.collection("users").document(me)
                          .collection("following").document(userId)
        batch.setData([:], forDocument: follower)
        batch.setData([:], forDocument: following)
        batch.commit(completion: completion)
    }

    func unfollow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(Self.authError())
        }
        let batch = db.batch()
        let follower = db.collection("users").document(userId)
                         .collection("followers").document(me)
        let following = db.collection("users").document(me)
                          .collection("following").document(userId)
        batch.deleteDocument(follower)
        batch.deleteDocument(following)
        batch.commit(completion: completion)
    }

    func isFollowing(userId: String,
                     completion: @escaping (Result<Bool,Error>) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(.failure(Self.authError()))
        }
        db.collection("users").document(userId)
          .collection("followers").document(me)
          .getDocument { snap, err in
              if let err { completion(.failure(err)); return }
              completion(.success(snap?.exists == true))
          }
    }

    func fetchFollowCount(userId: String,
                          type: String,
                          completion: @escaping (Result<Int,Error>) -> Void) {
        db.collection("users").document(userId)
          .collection(type)
          .getDocuments { snap, err in
              if let err { completion(.failure(err)); return }
              completion(.success(snap?.documents.count ?? 0))
          }
    }

    // ==================================================================
    // MARK:  Private helpers
    // ==================================================================

    /// `#hashtag` extractor (case-insensitive, deduped, lower-cased)
    private static func extractHashtags(from caption: String) -> [String] {
        let pattern = "(?:\\s|^)#(\\w+)"
        guard let rx = try? NSRegularExpression(pattern: pattern,
                                                options: .caseInsensitive)
        else { return [] }

        let nsRange = NSRange(caption.startIndex..., in: caption)
        let matches = rx.matches(in: caption, range: nsRange)
        let tags = matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: caption) else { return nil }
            return caption[r].lowercased()
        }
        return Array(Set(tags))
    }

    // Quick NSError helpers
    private static func authError() -> NSError {
        NSError(domain: "Auth", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
    }
    private static func imageError() -> NSError {
        NSError(domain: "Image", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Image conversion failed"])
    }
    private static func storageURLError() -> NSError {
        NSError(domain: "Storage", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No download URL"])
    }

    /// Shared doc→Post mapping used by both home-feed and Explore queries
    fileprivate static func decodePost(doc: QueryDocumentSnapshot) -> Post? {
        let d = doc.data()
        guard
            let uid       = d["userId"]    as? String,
            let imageURL  = d["imageURL"]  as? String,
            let caption   = d["caption"]   as? String,
            let ts        = d["timestamp"] as? Timestamp,
            let likes     = d["likes"]     as? Int,
            let isLiked   = d["isLiked"]   as? Bool
        else { return nil }

        return Post(
            id:        doc.documentID,
            userId:    uid,
            imageURL:  imageURL,
            caption:   caption,
            timestamp: ts.dateValue(),
            likes:     likes,
            isLiked:   isLiked,
            latitude:  d["latitude"]  as? Double,
            longitude: d["longitude"] as? Double,
            temp:      d["temp"]      as? Double,
            hashtags:  d["hashtags"]  as? [String] ?? []
        )
    }
}
