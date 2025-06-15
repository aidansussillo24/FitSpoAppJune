//
//  NetworkService+OutfitScan.swift
//  FitSpo
//

import Foundation
import FirebaseFunctions

// ───────── Cloud‑Function DTOs ─────────

struct ScanOutfitResponse: Decodable {
    let postId   : String
    let replicate: ReplicateJob
}

struct ReplicateJob: Decodable {
    let id     : String
    let status : String          // starting / processing / succeeded / failed
    let output : ReplicateOutput?
}

struct ReplicateOutput: Decodable {
    struct JsonData: Decodable   { let objects: [DetectedObject] }
    let json_data: JsonData
}

/// Accepts OWL‑ViT “label”, FashionPedia “category”, or a fallback “name”
struct DetectedObject: Decodable, Identifiable {          // 👈🏻 only *Decodable*
    let id         = UUID()
    let name       : String
    let confidence : Double
    let bbox       : [Double]

    private enum CodingKeys: String, CodingKey {
        case name, label, category, confidence, score, bbox, box
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name       = try c.decodeIfPresent(String.self, forKey: .name)
                  ?? c.decodeIfPresent(String.self, forKey: .label)
                  ?? c.decodeIfPresent(String.self, forKey: .category)
                  ?? "item"
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
                  ?? c.decodeIfPresent(Double.self, forKey: .score)
                  ?? 0
        bbox       = try c.decodeIfPresent([Double].self, forKey: .bbox)
                  ?? c.decodeIfPresent([Double].self, forKey: .box)
                  ?? []
    }
}

// ───────── Outfit‑scan helpers ─────────

@MainActor
extension NetworkService {

    /// ① Kick off Cloud Function
    static func scanOutfit(postId: String,
                           imageURL: String) async throws -> ReplicateJob {
        let functions = Functions.functions(region: "us-central1")    // new fetcher
        let body: [String: Any] = ["postId": postId, "imageURL": imageURL]
        let data = try await functions.httpsCallable("scanOutfit").call(body)
        return try JSONDecoder().decode(
            ScanOutfitResponse.self,
            from: JSONSerialization.data(withJSONObject: data.data)
        ).replicate
    }

    /// ② Poll until the model finishes (≈30 s max)
    static func waitForReplicate(prediction job: ReplicateJob) async throws -> ReplicateJob {
        var current = job; var tries = 0
        while ["starting","processing"].contains(current.status) {
            try await Task.sleep(for: .seconds(2))
            current = try await fetchReplicate(jobID: current.id)
            guard tries < 15 else { throw URLError(.timedOut) }
            tries += 1
        }
        return current
    }

    /// latest job JSON
    private static func fetchReplicate(jobID: String) async throws -> ReplicateJob {
        let functions = Functions.functions(region: "us-central1")
        let res = try await functions
            .httpsCallable("fetchReplicate")
            .call(["jobId": jobID])
        return try JSONDecoder().decode(
            ReplicateJob.self,
            from: JSONSerialization.data(withJSONObject: res.data)
        )
    }
}
