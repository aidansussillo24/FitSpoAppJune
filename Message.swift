import Foundation

struct Message: Identifiable {
    let id: String
    let senderId: String
    let text: String
    let timestamp: Date
}
