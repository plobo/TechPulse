import CryptoKit
import Foundation

/// What article text the model was allowed to see (publisher rules via `ArticleBodyPolicy`).
enum AIInputBasis: String, Codable, Sendable, Hashable {
    case fullText, excerptOnly, metadataOnly

    /// Visible label when the AI did not see the full article; nil for full text.
    var label: String? {
        switch self {
        case .fullText: nil
        case .excerptOnly: "Based on the excerpt only"
        case .metadataOnly: "Based on title and summary only"
        }
    }
}

enum SummaryType: String, Codable, Sendable, CaseIterable, Hashable {
    case thirtySeconds, twoMinutes, detailed

    var title: String {
        switch self {
        case .thirtySeconds: "30-second"
        case .twoMinutes: "2-minute"
        case .detailed: "Detailed"
        }
    }

    init(_ length: SummaryLength) {
        switch length {
        case .thirtySeconds: self = .thirtySeconds
        case .twoMinutes: self = .twoMinutes
        case .detailed: self = .detailed
        }
    }
}

enum AIFeature: String, Codable, Sendable, Hashable {
    case summary, question, codeExplanation, diagram
}

/// The permitted, budgeted article text handed to a model.
struct AIArticleInput: Sendable, Hashable {
    let articleID: ArticleID
    let title: String
    let sourceName: String
    let text: String
    let basis: AIInputBasis
    /// SHA-256 of basis + text; changes when the permitted input changes.
    let fingerprint: String

    static func make(from article: Article, budget: Int = AIPrompts.articleBudget) -> AIArticleInput {
        var header = ["Title: \(article.title)", "Source: \(article.sourceName)"]
        if let summary = article.summary {
            header.append("Publisher summary: \(truncate(summary, to: min(summaryCap, max(budget / 3, 80))))")
        }
        let basis: AIInputBasis
        var body: String?
        switch ArticleBodyPolicy.body(for: article) {
        case let .full(text):
            basis = .fullText
            body = text
        case let .excerpt(text):
            basis = .excerptOnly
            body = text
        case .linkOnly:
            basis = .metadataOnly
        }
        var text = header.joined(separator: "\n")
        if let body {
            let remaining = max(budget - text.count - 2, 0)
            text += "\n\n" + truncate(body, to: remaining)
        }
        return AIArticleInput(articleID: article.id, title: article.title, sourceName: article.sourceName,
                              text: text, basis: basis, fingerprint: fingerprint(basis: basis, text: text))
    }

    static let summaryCap = 600

    /// Smaller input used for one retry after the model reports a context overflow.
    static func reduced(from article: Article) -> AIArticleInput {
        make(from: article, budget: AIPrompts.articleBudget / 2)
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        var cut = String(text.prefix(limit))
        if let space = cut.lastIndex(where: \.isWhitespace) { cut = String(cut[..<space]) }
        return cut + " [truncated]"
    }

    static func fingerprint(basis: AIInputBasis, text: String) -> String {
        SHA256.hash(data: Data((basis.rawValue + "\n" + text).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum AIRole: String, Codable, Sendable { case user, assistant }

struct AIMessage: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let role: AIRole
    let content: String
    let timestamp: Date
    /// Which model wrote an assistant message (nil for user messages and pre-fix data).
    var provider: AIProviderInfo? = nil
}

struct AIConversation: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let articleID: ArticleID?
    let articleTitle: String?
    let basis: AIInputBasis?
    var messages: [AIMessage]
    var updatedAt: Date
}

enum AIServiceError: Error, Equatable, Sendable {
    case unavailable
    case rateLimited
    case busy
    case requestTooLarge
    case contextTooLarge
    case guardrail
    case invalidDiagram(String)
    case generationFailed

    var message: String {
        switch self {
        case .unavailable: "AI isn’t available on this device."
        case .rateLimited: "Too many AI requests. Please wait a moment."
        case .busy: "Already working on this. Please wait."
        case .requestTooLarge: "That’s too long (or empty). Please shorten it."
        case .contextTooLarge: "This is too long for the on-device model."
        case .guardrail: "The on-device model declined this request."
        case let .invalidDiagram(reason): "The generated diagram wasn’t valid (\(reason)). Try again."
        case .generationFailed: "The AI couldn’t generate a response. Try again."
        }
    }
}
