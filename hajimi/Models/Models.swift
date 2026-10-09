import Foundation

struct UserProfile: Codable, Equatable, Hashable {
    let id: String
    let email: String
    let name: String
    let picture: String?
}

struct ChatSession: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var title: String
    let createdAt: Date
    let updatedAt: Date
}

enum MessageRole: String, Codable, Equatable, Hashable {
    case user
    case assistant
}

struct ChatMessage: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let role: MessageRole
    var content: String
    let createdAt: Date
}

struct AuthSession: Equatable {
    let token: String
    let user: UserProfile
}

struct ChatStreamEvent: Decodable {
    let type: String
    let text: String?
    let message: ChatMessage?
    let session: ChatSession?
    let error: String?
}
