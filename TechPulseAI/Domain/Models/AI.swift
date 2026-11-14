import Foundation

enum SummaryType: String, Sendable, Codable, Hashable {
    case thirtySeconds, twoMinutes, detailed
}

struct AIProviderInfo: Sendable, Hashable, Codable {
    let provider: String
    let model: String
    let promptVersion: String
}

/// AI-generated article summary. Always rendered with `GeneratedContentBadge`.
struct ArticleSummary: Sendable, Hashable, Codable {
    let articleID: ArticleID
    let type: SummaryType
    let text: String
    let providerInfo: AIProviderInfo
    let createdAt: Date
}

enum AIRole: String, Sendable, Codable { case user, assistant }

struct AIMessage: Identifiable, Sendable, Hashable, Codable {
    let id: UUID
    let role: AIRole
    let content: String
    let timestamp: Date
    let referencedArticleIDs: [ArticleID]
}

struct AIConversation: Identifiable, Sendable, Hashable, Codable {
    let id: UUID
    let articleID: ArticleID?
    var messages: [AIMessage]
}

enum AIServiceError: Error, Equatable {
    /// No backend AI endpoint configured or the user has not enabled AI features.
    case unavailable
    case rateLimited
    case requestTooLarge
}
