import Foundation

/// A single in-app notification for the Activity screen.
struct UserNotification: Identifiable, Codable {
    enum Kind: String, Codable { 
        case mention, comment, like, tag, follow, likeComment, reply, save
    }

    let id: String
    let postId: String
    let fromUserId: String
    let fromUsername: String
    let fromAvatarURL: String?
    let text: String
    let kind: Kind
    let timestamp: Date

    var dictionary: [String: Any] {
        [
            "id":            id,
            "postId":        postId,
            "fromUserId":    fromUserId,
            "fromUsername":  fromUsername,
            "fromAvatarURL": fromAvatarURL as Any,
            "text":          text,
            "kind":          kind.rawValue,
            "timestamp":     timestamp.timeIntervalSince1970
        ]
    }
    
    var timeAgo: String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(timestamp)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        } else if timeInterval < 604800 {
            let days = Int(timeInterval / 86400)
            return "\(days)d"
        } else if timeInterval < 2592000 {
            let weeks = Int(timeInterval / 604800)
            return "\(weeks)w"
        } else {
            let months = Int(timeInterval / 2592000)
            return "\(months)mo"
        }
    }
    
    var timeSection: String {
        let now = Date()
        let calendar = Calendar.current
        let timeInterval = now.timeIntervalSince(timestamp)
        
        if calendar.isDateInToday(timestamp) {
            return "Today"
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else if timeInterval < 604800 { // Less than a week
            return "This week"
        } else if timeInterval < 2592000 { // Less than a month
            return "This month"
        } else {
            return "Earlier"
        }
    }

    init(id: String = UUID().uuidString,
         postId: String,
         fromUserId: String,
         fromUsername: String,
         fromAvatarURL: String?,
         text: String,
         kind: Kind,
         timestamp: Date = .init()) {
        self.id = id
        self.postId = postId
        self.fromUserId = fromUserId
        self.fromUsername = fromUsername
        self.fromAvatarURL = fromAvatarURL
        self.text = text
        self.kind = kind
        self.timestamp = timestamp
    }

    init?(from dict: [String: Any]) {
        guard
            let id       = dict["id"]       as? String,
            let postId   = dict["postId"]   as? String,
            let uid      = dict["fromUserId"] as? String,
            let uname    = dict["fromUsername"] as? String,
            let text     = dict["text"]     as? String,
            let kindRaw  = dict["kind"]     as? String,
            let ts       = dict["timestamp"] as? TimeInterval,
            let kind     = Kind(rawValue: kindRaw)
        else { return nil }
        self.id = id
        self.postId = postId
        self.fromUserId = uid
        self.fromUsername = uname
        self.fromAvatarURL = dict["fromAvatarURL"] as? String
        self.text = text
        self.kind = kind
        self.timestamp = Date(timeIntervalSince1970: ts)
    }
}
