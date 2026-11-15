#if DEBUG
import Foundation

/// Debug-only stand-in that returns deterministic, obviously fake output so AI
/// screens can be exercised in the simulator and tests. Never compiled into Release.
struct DemoAIService: AIService {
    static let marker = "[Demo AI — fake output] "
    var delay: Duration = .zero

    var providerInfo: AIProviderInfo { AIProviderInfo(provider: "Demo AI", model: "demo", isDemo: true) }

    func availability() async -> AIAvailability { .available }

    private func pause() async throws {
        if delay > .zero { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
    }

    func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String {
        try await pause()
        switch type {
        case .thirtySeconds:
            return Self.marker + "\n• Placeholder point about “\(input.title)”.\n• Second placeholder point.\n• This is not a real summary."
        case .twoMinutes:
            return Self.marker + "\nContext: placeholder context for “\(input.title)”.\nKey points: placeholder.\nImplications: placeholder."
        case .detailed:
            return Self.marker + "\nConcepts: placeholder.\nTerminology: placeholder.\nTrade-offs: placeholder. Generated without a model."
        }
    }

    func answer(_ question: String, input: AIArticleInput, history: [AIMessage]) async throws -> String {
        try await pause()
        return Self.marker + "This is a canned answer to “\(question.prefix(60))”. A real model would answer from the article text."
    }

    func explainCode(_ snippet: String) async throws -> CodeExplanation {
        try await pause()
        return CodeExplanation(language: "Swift (demo guess)",
                               explanation: Self.marker + "This placeholder explanation describes the snippet in general terms.",
                               risks: ["Placeholder risk: no real analysis was performed."])
    }

    func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram {
        try await pause()
        return ArchitectureDiagram(
            title: "Demo architecture (fake)",
            components: [
                .init(id: "client", name: "Client App", kind: "client", detail: "Demo component"),
                .init(id: "api", name: "API Gateway", kind: "service", detail: "Demo component"),
                .init(id: "worker", name: "Worker", kind: "service", detail: "Demo component"),
                .init(id: "db", name: "Database", kind: "database", detail: "Demo component"),
            ],
            connections: [
                .init(from: "client", to: "api", label: "HTTPS"),
                .init(from: "api", to: "worker", label: "queue"),
                .init(from: "worker", to: "db", label: "writes"),
                .init(from: "api", to: "db", label: "reads"),
            ])
    }
}
#endif
