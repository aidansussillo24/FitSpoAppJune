//
//  NetworkService.swift
//  FitSpo
//
//  Core networking layer + Firestore helpers.
//  Updated 2025‑06‑18: caches outfit‑scan results at upload
//  and maps them back into `Post.outfitItems`.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Network
import UIKit

// ─────────────────────────────────────────────────────────────
final class NetworkService {

    // MARK: – Singleton + reachability
    static let shared = NetworkService()
    private init() { startPathMonitor() }

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "FitSpo.NetMonitor")
    private var pathStatus: NWPath.Status = .satisfied
    static var isOnline: Bool { shared.pathStatus == .satisfied }

    private func startPathMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.pathStatus = path.status
        }
        monitor.start(queue: queue)
    }

    // MARK: – Firebase handles
    let db      = Firestore.firestore()
    private let storage = Storage.storage().reference()

    // ====================================================================
    // MARK:  User profile
    // ====================================================================
    func createUserProfile(userId: String,
                           data: [String : Any]) async throws {
        var d = data
        if let username = data["username"]    as? String { d["username_lc"]   = username.lowercased() }
        if let name     = data["displayName"] as? String { d["displayName_lc"] = name.lowercased()  }
        try await db.collection("users").document(userId).setData(d)
    }

    // ====================================================================
    // MARK:  Outfit‑item decode helper   ← NEW
    // ====================================================================
    private static func parseOutfitItems(_ raw: Any?) -> [OutfitItem] {
        guard let arr = raw as? [[String:Any]] else { return [] }
        return arr.compactMap { dict in
            guard
                let label = dict["label"]   as? String,
                let shop  = dict["shopURL"] as? String
            else { return nil }
            let brand = dict["brand"] as? String ?? ""
            return OutfitItem(id: UUID().uuidString,
                              label: label,
                              brand: brand,
                              shopURL: shop)
        }
    }

    // ====================================================================
    // MARK:  Upload Post  (hashtags + face‑tags + outfit‑scan caching)
    // ====================================================================
    func uploadPost(
        image: UIImage,
        caption: String,
        latitude: Double?,
        longitude: Double?,
        tags: [UserTag],
        completion: @escaping (Result<Void,Error>) -> Void
    ) {

        guard let me = Auth.auth().currentUser else {
            return completion(.failure(Self.authError()))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            return completion(.failure(Self.imageError()))
        }

        // 1️⃣ Upload image binary
        let imgID = UUID().uuidString
        let ref   = storage.child("post_images/\(imgID).jpg")
        ref.putData(jpeg, metadata: nil) { [weak self] _, err in
            if let err { return completion(.failure(err)) }

            ref.downloadURL { url, err in
                if let err { return completion(.failure(err)) }
                guard let self, let url else {
                    return completion(.failure(Self.storageURLError()))
                }

                // 2️⃣ Assemble base post payload
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

                // 3️⃣ Create the Firestore doc immediately
                let doc = self.db.collection("posts").document()
                doc.setData(post) { err in
                    if let err { return completion(.failure(err)) }

                    // 4️⃣ Save face‑tags sub‑collection (async batch)
                    let batch = self.db.batch()
                    tags.forEach { t in
                        let sub = doc.collection("tags").document(t.id)
                        batch.setData([
                            "uid"         : t.id,
                            "displayName" : t.displayName,
                            "xNorm"       : t.xNorm,
                            "yNorm"       : t.yNorm
                        ], forDocument: sub)
                    }
                    batch.commit { err in
                        // Notify UI that the post is live
                        NotificationCenter.default.post(name: .didUploadPost, object: nil)
                        err == nil ? completion(.success(()))
                                   : completion(.failure(err!))
                    }
                }

                // 5️⃣ Fire‑and‑forget: run outfit‑scan and cache its result
                Task.detached { [weak self] in
                    guard let self else { return }
                    do {
                        let kick = try await NetworkService.scanOutfit(
                            postId: doc.documentID,
                            imageURL: url.absoluteString
                        )
                        let fin  = try await NetworkService.waitForReplicate(prediction: kick)
                        let detections = fin.output?.json_data.objects ?? []

                        let mapped: [[String:String]] = detections.map { det in
                            [
                                "label"  : det.name,
                                "brand"  : "",
                                "shopURL": "https://www.google.com/search?q="
                                         + det.name.addingPercentEncoding(
                                            withAllowedCharacters: .urlQueryAllowed
                                           )!
                            ]
                        }

                        try await self.db.collection("posts")
                            .document(doc.documentID)
                            .updateData(["scanResults": mapped])

                    } catch {
                        print("⚠️ Outfit scan failed for post \(doc.documentID):",
                              error.localizedDescription)
                    }
                }
            }
        }
    }

    // ====================================================================
    // MARK:  Fetch Posts (home feed)
    // ====================================================================
    func fetchPosts(completion: @escaping (Result<[Post],Error>) -> Void) {
        db.collection("posts")
            .order(by: "timestamp", descending: true)
            .getDocuments { snap, err in
                if let err { completion(.failure(err)); return }
                let posts = snap?.documents.compactMap(Self.decodePost) ?? []
                completion(.success(posts))
            }
    }

    // ====================================================================
    // MARK:  Tags helper
    // ====================================================================
    func fetchTags(for postId: String,
                   completion: @escaping (Result<[UserTag],Error>) -> Void) {
        db.collection("posts").document(postId)
            .collection("tags")
            .getDocuments { snap, err in
                if let err { completion(.failure(err)); return }
                let list: [UserTag] = snap?.documents.compactMap { d in
                    guard
                        let x = d["xNorm"]       as? Double,
                        let y = d["yNorm"]       as? Double,
                        let n = d["displayName"] as? String
                    else { return nil }
                    return UserTag(
                        id: d.documentID,
                        xNorm: x, yNorm: y,
                        displayName: n
                    )
                } ?? []
                completion(.success(list))
            }
    }

    // ====================================================================
    // MARK:  Likes
    // ====================================================================
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

    // ====================================================================
    // MARK:  Delete Post
    // ====================================================================
    func deletePost(id: String,
                    completion: @escaping (Result<Void,Error>) -> Void) {

        let ref = db.collection("posts").document(id)
        ref.getDocument { snap, err in
            if let err { return completion(.failure(err)) }

            guard
                let d   = snap?.data(),
                let str = d["imageURL"] as? String,
                let url = URL(string: str)
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

    // ====================================================================
    // MARK:  Follow helpers
    // ====================================================================
    func follow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(Self.authError())
        }
        let batch = db.batch()
        batch.setData([:], forDocument: db.collection("users").document(userId)
                                   .collection("followers").document(me))
        batch.setData([:], forDocument: db.collection("users").document(me)
                                   .collection("following").document(userId))
        batch.commit(completion: completion)
    }

    func unfollow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(Self.authError())
        }
        let batch = db.batch()
        batch.deleteDocument(db.collection("users").document(userId)
                               .collection("followers").document(me))
        batch.deleteDocument(db.collection("users").document(me)
                               .collection("following").document(userId))
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
                          type: String,          // "followers" or "following"
                          completion: @escaping (Result<Int,Error>) -> Void) {
        db.collection("users").document(userId)
            .collection(type)
            .getDocuments { snap, err in
                if let err { completion(.failure(err)); return }
                completion(.success(snap?.documents.count ?? 0))
            }
    }

    // ====================================================================
    // MARK:  Private helpers
    // ====================================================================
    private static func extractHashtags(from caption: String) -> [String] {
        let pattern = "(?:\\s|^)#(\\w+)"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange  = NSRange(caption.startIndex..., in: caption)
        let matches  = rx.matches(in: caption, range: nsRange)
        let tags = matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: caption) else { return nil }
            return caption[r].lowercased()
        }
        return Array(Set(tags))
    }

    private static func authError() -> NSError {
        NSError(domain: "Auth", code: -1,
                userInfo: [NSLocalizedDescriptionKey:"Not signed in"])
    }
    private static func imageError() -> NSError {
        NSError(domain: "Image", code: -1,
                userInfo: [NSLocalizedDescriptionKey:"Image conversion failed"])
    }
    private static func storageURLError() -> NSError {
        NSError(domain: "Storage", code: -1,
                userInfo: [NSLocalizedDescriptionKey:"No download URL"])
    }

    // ====================================================================
    // MARK:  Shared doc→Post mapper (now fills outfitItems)
    // ====================================================================
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
            id:          doc.documentID,
            userId:      uid,
            imageURL:    imageURL,
            caption:     caption,
            timestamp:   ts.dateValue(),
            likes:       likes,
            isLiked:     isLiked,
            latitude:    d["latitude"]      as? Double,
            longitude:   d["longitude"]     as? Double,
            temp:        d["temp"]          as? Double,
            outfitItems: parseOutfitItems(d["scanResults"]),
            hashtags:    d["hashtags"]      as? [String] ?? []
        )
    }
}
//  End of NetworkService.swift
