import Foundation
import FirebaseAuth
import FirebaseFirestore

extension NetworkService {
    /// Fetch all chats involving the current user (manual decoding)
    func fetchChats(completion: @escaping (Result<[Chat], Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let firestore = Firestore.firestore()
        firestore.collection("chats")
            .whereField("participants", arrayContains: uid)
            .order(by: "lastTimestamp", descending: true)
            .getDocuments { snap, err in
                if let err = err {
                    return completion(.failure(err))
                }
                let chats: [Chat] = snap?.documents.compactMap { doc in
                    let data = doc.data()
                    guard
                        let parts   = data["participants"] as? [String],
                        let lastMsg = data["lastMessage"] as? String,
                        let ts      = data["lastTimestamp"] as? Timestamp
                    else { return nil }
                    return Chat(
                        id: doc.documentID,
                        participants: parts,
                        lastMessage: lastMsg,
                        lastTimestamp: ts.dateValue()
                    )
                } ?? []
                completion(.success(chats))
            }
    }

    /// Create a new chat with specified participants
    func createChat(
        participants: [String],
        completion: @escaping (Result<Chat, Error>) -> Void
    ) {
        let firestore = Firestore.firestore()
        let now = Date()
        let data: [String: Any] = [
            "participants": participants,
            "lastMessage":   "",
            "lastTimestamp": Timestamp(date: now)
        ]
        let chatRef = firestore.collection("chats").document()
        chatRef.setData(data) { err in
            if let err = err {
                return completion(.failure(err))
            }
            let chat = Chat(
                id: chatRef.documentID,
                participants: participants,
                lastMessage: "",
                lastTimestamp: now
            )
            completion(.success(chat))
        }
    }

    /// Send a message and update the chat’s lastMessage/lastTimestamp
    func sendMessage(
        chatId: String,
        text: String,
        completion: @escaping (Error?) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let firestore = Firestore.firestore()
        let now = Date()
        let data: [String: Any] = [
            "senderId":   uid,
            "text":       text,
            "timestamp":  Timestamp(date: now)
        ]
        let msgRef = firestore
            .collection("chats")
            .document(chatId)
            .collection("messages")
            .document()
        msgRef.setData(data) { err in
            if let err = err {
                return completion(err)
            }
            // update parent chat document
            firestore.collection("chats").document(chatId)
                .updateData([
                    "lastMessage":   text,
                    "lastTimestamp": Timestamp(date: now)
                ]) { updateErr in
                    completion(updateErr)
                }
        }
    }

    /// Listen in real-time for new messages (manual decoding)
    @discardableResult
    func observeMessages(
        chatId: String,
        handler: @escaping (Result<Message, Error>) -> Void
    ) -> ListenerRegistration {
        let firestore = Firestore.firestore()
        return firestore.collection("chats")
            .document(chatId)
            .collection("messages")
            .order(by: "timestamp")
            .addSnapshotListener { snap, err in
                if let err = err {
                    handler(.failure(err))
                } else {
                    snap?.documentChanges.forEach { change in
                        guard change.type == .added else { return }
                        let doc  = change.document
                        let data = doc.data()
                        guard
                            let senderId = data["senderId"] as? String,
                            let text     = data["text"]     as? String,
                            let ts       = data["timestamp"] as? Timestamp
                        else { return }
                        let msg = Message(
                            id:        doc.documentID,
                            senderId:  senderId,
                            text:      text,
                            timestamp: ts.dateValue()
                        )
                        handler(.success(msg))
                    }
                }
            }
    }
}
