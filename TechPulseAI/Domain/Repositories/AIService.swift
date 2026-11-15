import Foundation

enum AIAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedOS

    var isAvailable: Bool { self == .available }

    var message: String {
        switch self {
        case .available: "On-device AI is ready."
        case .deviceNotEligible: "This device doesn’t support Apple Intelligence, which TechPulse’s on-device AI needs."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in the Settings app to use AI features."
        case .modelNotReady: "Apple’s on-device model is still downloading. Try again later."
        case .unsupportedOS: "AI features need iOS 26 or later on an Apple Intelligence device."
        }
    }
}

struct AIProviderInfo: Codable, Sendable, Hashable {
    let provider: String
    let model: String
    let isDemo: Bool
}

struct CodeExplanation: Codable, Sendable, Hashable {
    let language: String
    let explanation: String
    let risks: [String]

    static let caveat = "AI explanations can be wrong and are not a security review."
}

/// Provider-neutral AI abstraction (plan §9). Implementations: Foundation Models
/// (on-device, iOS 26), Demo (Debug only), Unavailable.
protocol AIService: Sendable {
    var providerInfo: AIProviderInfo { get }
    func availability() async -> AIAvailability
    func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String
    func answer(_ question: String, input: AIArticleInput, history: [AIMessage]) async throws -> String
    func explainCode(_ snippet: String) async throws -> CodeExplanation
    /// Raw model output; callers must run `DiagramValidator.validate` before use.
    func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram
}

struct UnavailableAIService: AIService {
    var reason: AIAvailability = .unsupportedOS

    init(reason: AIAvailability = .unsupportedOS) { self.reason = reason }

    var providerInfo: AIProviderInfo { AIProviderInfo(provider: "None", model: "none", isDemo: false) }
    func availability() async -> AIAvailability { reason }
    func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String { throw AIServiceError.unavailable }
    func answer(_ question: String, input: AIArticleInput, history: [AIMessage]) async throws -> String { throw AIServiceError.unavailable }
    func explainCode(_ snippet: String) async throws -> CodeExplanation { throw AIServiceError.unavailable }
    func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram { throw AIServiceError.unavailable }
}

/// The real service plus the optional Debug-only demo stand-in.
struct AIServices: Sendable {
    let real: any AIService
    let demo: (any AIService)?

    func active(demoEnabled: Bool) -> any AIService {
        if demoEnabled, let demo { return demo }
        return real
    }
}
