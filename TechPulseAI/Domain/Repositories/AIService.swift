import Foundation

/// Provider-neutral AI abstraction (plan §9). Implementations must route through
/// the TechPulse backend; provider credentials never ship in the app.
protocol AIService: Sendable {
    var isAvailable: Bool { get }
    func summarize(_ article: Article, type: SummaryType) async throws -> ArticleSummary
    func ask(_ question: String, about article: Article, history: [AIMessage]) async throws -> AIMessage
}

/// Default until the Phase 2 backend AI endpoints exist.
struct UnavailableAIService: AIService {
    var isAvailable: Bool { false }
    func summarize(_ article: Article, type: SummaryType) async throws -> ArticleSummary { throw AIServiceError.unavailable }
    func ask(_ question: String, about article: Article, history: [AIMessage]) async throws -> AIMessage {
        throw AIServiceError.unavailable
    }
}
