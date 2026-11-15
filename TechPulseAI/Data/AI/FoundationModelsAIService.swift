import Foundation

/// Pure mapping from the framework's unavailability reason names to app states.
enum AIAvailabilityMapper {
    static func map(isAvailable: Bool, reason: String?) -> AIAvailability {
        if isAvailable { return .available }
        switch reason {
        case "deviceNotEligible": return .deviceNotEligible
        case "appleIntelligenceNotEnabled": return .appleIntelligenceNotEnabled
        case "modelNotReady": return .modelNotReady
        default: return .deviceNotEligible
        }
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device model (iOS 26, Apple Intelligence devices).
/// Output quality is unverified in this repo's automated tests (no capable device/simulator).
@available(iOS 26, *)
struct FoundationModelsAIService: AIService {
    var providerInfo: AIProviderInfo {
        AIProviderInfo(provider: "Apple Foundation Models", model: "SystemLanguageModel.default", isDemo: false)
    }

    func availability() async -> AIAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case let .unavailable(reason):
            return AIAvailabilityMapper.map(isAvailable: false, reason: String(describing: reason))
        }
    }

    func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String {
        try await text(AIPrompts.summary(input, type: type), feature: .summary)
    }

    func answer(_ question: String, input: AIArticleInput, history: [AIMessage]) async throws -> String {
        try await text(try AIPrompts.question(question, input: input, history: history), feature: .question)
    }

    func explainCode(_ snippet: String) async throws -> CodeExplanation {
        let prompt = try AIPrompts.code(snippet)
        let result: GenCodeExplanation = try await generate(prompt, feature: .codeExplanation)
        return CodeExplanation(language: result.language, explanation: result.explanation, risks: result.risks)
    }

    func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram {
        let result: GenDiagram = try await generate(AIPrompts.diagram(input), feature: .diagram)
        return ArchitectureDiagram(
            title: result.title,
            components: result.components.map { .init(id: $0.id, name: $0.name, kind: $0.kind, detail: $0.detail) },
            connections: result.connections.map { .init(from: $0.from, to: $0.to, label: $0.label) })
    }

    // MARK: - Private

    private func guardAvailable() async throws {
        guard await availability() == .available else { throw AIServiceError.unavailable }
    }

    private func text(_ prompt: String, feature: AIFeature) async throws -> String {
        try await guardAvailable()
        let session = LanguageModelSession(instructions: AIPrompts.instructions(for: feature))
        do {
            return try await session.respond(to: prompt).content
        } catch {
            throw Self.map(error)
        }
    }

    private func generate<T: Generable>(_ prompt: String, feature: AIFeature) async throws -> T {
        try await guardAvailable()
        let session = LanguageModelSession(instructions: AIPrompts.instructions(for: feature))
        do {
            return try await session.respond(to: prompt, generating: T.self).content
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        guard let generation = error as? LanguageModelSession.GenerationError else { return AIServiceError.generationFailed }
        switch generation {
        case .exceededContextWindowSize: return AIServiceError.contextTooLarge
        case .guardrailViolation: return AIServiceError.guardrail
        case .rateLimited, .concurrentRequests: return AIServiceError.rateLimited
        default: return AIServiceError.generationFailed
        }
    }
}

@available(iOS 26, *)
@Generable
private struct GenCodeExplanation {
    @Guide(description: "Programming language and framework, e.g. 'Swift / SwiftUI'")
    var language: String
    @Guide(description: "Plain-language explanation of what the code does")
    var explanation: String
    @Guide(description: "Notable risks, bugs or gotchas; empty if none")
    var risks: [String]
}

@available(iOS 26, *)
@Generable
private struct GenDiagram {
    @Guide(description: "Short diagram title")
    var title: String
    @Guide(description: "At most 12 components")
    var components: [GenComponent]
    @Guide(description: "At most 20 connections between component ids")
    var connections: [GenConnection]
}

@available(iOS 26, *)
@Generable
private struct GenComponent {
    @Guide(description: "Identifier: starts with a letter; letters, digits, underscores only")
    var id: String
    @Guide(description: "Short display name")
    var name: String
    @Guide(description: "Kind, e.g. client, service, database, queue, cache")
    var kind: String
    @Guide(description: "One short sentence about its role")
    var detail: String
}

@available(iOS 26, *)
@Generable
private struct GenConnection {
    @Guide(description: "Source component id")
    var from: String
    @Guide(description: "Target component id")
    var to: String
    @Guide(description: "Short label, e.g. 'HTTPS', 'reads'")
    var label: String
}
#endif
