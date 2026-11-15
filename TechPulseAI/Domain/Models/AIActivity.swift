import Foundation

enum AIArtifactKind: String, Codable, Sendable, Hashable {
    case summary, codeExplanation, diagram

    var title: String {
        switch self {
        case .summary: "Summary"
        case .codeExplanation: "Code explanation"
        case .diagram: "Architecture diagram"
        }
    }
}

/// A saved AI output (summary, code explanation or diagram) with its provenance.
struct AIArtifact: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let kind: AIArtifactKind
    let cacheKey: String
    let articleID: ArticleID?
    let articleTitle: String?
    let summaryType: SummaryType?
    let basis: AIInputBasis?
    let provider: AIProviderInfo
    let promptVersion: String
    let text: String?
    let code: CodeExplanation?
    let diagram: ArchitectureDiagram?
    let createdAt: Date
}

enum AICacheKey {
    private static func key(_ parts: [String]) -> String { parts.joined(separator: "|") }

    static func summary(_ input: AIArticleInput, type: SummaryType, provider: AIProviderInfo) -> String {
        key([input.articleID, AIFeature.summary.rawValue, type.rawValue, input.fingerprint, AIPrompts.version,
             provider.model, provider.isDemo ? "demo" : "real"])
    }

    static func diagram(_ input: AIArticleInput, provider: AIProviderInfo) -> String {
        key([input.articleID, AIFeature.diagram.rawValue, input.fingerprint, AIPrompts.version,
             provider.model, provider.isDemo ? "demo" : "real"])
    }

    /// Code explanations are history entries, not a lookup cache: unique per request.
    static func codeExplanation(id: UUID) -> String {
        key([AIFeature.codeExplanation.rawValue, id.uuidString])
    }
}

/// Row in the AI Reader activity list.
enum AIActivityItem: Identifiable, Codable, Sendable, Hashable {
    case artifact(AIArtifact)
    case conversation(AIConversation)

    var id: UUID {
        switch self {
        case let .artifact(a): a.id
        case let .conversation(c): c.id
        }
    }

    var date: Date {
        switch self {
        case let .artifact(a): a.createdAt
        case let .conversation(c): c.updatedAt
        }
    }
}
