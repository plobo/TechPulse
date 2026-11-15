import Foundation

/// State of one AI output, with AI-specific error messages.
enum AIOutputState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    var errorMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// Shared AI plumbing for view models: picks the active service, enforces the
/// user's switch, throttles via the gate and counts successful generations.
@MainActor
struct AIRuntime {
    let dependencies: AppDependencies
    let library: LibraryStore

    var demoActive: Bool {
        dependencies.ai.demo != nil && (dependencies.forcesDemoAI || library.preferences.demoAIEnabled)
    }

    var service: any AIService { dependencies.ai.active(demoEnabled: demoActive) }
    var userEnabled: Bool { dependencies.forcesDemoAI || library.preferences.aiFeaturesEnabled }

    func run<T: Sendable>(key: String, _ work: () async throws -> T) async throws -> T {
        try await dependencies.aiGate.begin(key)
        do {
            let result = try await work()
            try Task.checkCancellation()
            await dependencies.aiGate.end(key)
            await library.updatePreferences { $0.aiGenerationCount += 1 }
            return result
        } catch {
            await dependencies.aiGate.end(key)
            throw error
        }
    }

    static func message(for error: any Error) -> String {
        if let ai = error as? AIServiceError { return ai.message }
        if let diagram = error as? DiagramValidationError { return AIServiceError.invalidDiagram(diagram.reason).message }
        return AIServiceError.generationFailed.message
    }
}

enum AIReport {
    /// Problem report for an AI output. Contains provenance only — never notes or history.
    static func text(for artifact: AIArtifact) -> String {
        let output: String = switch artifact.kind {
        case .summary: artifact.text ?? ""
        case .codeExplanation: artifact.code.map { "\($0.language): \($0.explanation)" } ?? ""
        case .diagram: artifact.diagram.map(DiagramTextDescription.text(for:)) ?? ""
        }
        return text(articleID: artifact.articleID, kind: artifact.kind.title, output: output,
                    provider: artifact.provider, promptVersion: artifact.promptVersion, basis: artifact.basis)
    }

    static func text(articleID: ArticleID?, kind: String, output: String, provider: AIProviderInfo,
                     promptVersion: String, basis: AIInputBasis?) -> String {
        """
        TechPulse AI — problem with AI output
        Kind: \(kind)
        Article ID: \(articleID ?? "—")
        Provider: \(provider.provider) (\(provider.model))\(provider.isDemo ? " [Demo AI — fake output]" : "")
        Prompt version: \(promptVersion)
        Input: \(basis?.label ?? (basis == .fullText ? "Full text" : "User-supplied"))
        Output:
        \(String(output.prefix(2000)))
        """
    }
}
