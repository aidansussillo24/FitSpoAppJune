//
//  Message.swift
//  FitSpo
//

import Foundation

/// A single chat message, either text, shared post, or shared profile
struct Message: Identifiable {
    let id: String
    let senderId: String
    let text: String?      // nil when this is a post share or profile share
    let postId: String?    // nil when this is a text message or profile share
    let profileUserId: String?    // nil when this is a text message or post share
    let profileDisplayName: String? // nil when this is a text message or post share
    let profileAvatarURL: String? // nil when this is a text message or post share
    let timestamp: Date
    
    init(id: String, senderId: String, text: String?, postId: String?, timestamp: Date, profileUserId: String? = nil, profileDisplayName: String? = nil, profileAvatarURL: String? = nil) {
        self.id = id
        self.senderId = senderId
        self.text = text
        self.postId = postId
        self.profileUserId = profileUserId
        self.profileDisplayName = profileDisplayName
        self.profileAvatarURL = profileAvatarURL
        self.timestamp = timestamp
    }
}
