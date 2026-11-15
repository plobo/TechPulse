import Foundation
import Observation

@MainActor
@Observable
final class CodeExplainerViewModel {
    let article: Article?
    var snippet = ""
    private(set) var result: AIOutputState<AIArtifact> = .idle
    private(set) var availability: AIAvailability?
    private var running: Task<Void, Never>?
    private let runtime: AIRuntime

    init(article: Article?, dependencies: AppDependencies, library: LibraryStore) {
        self.article = article
        self.runtime = AIRuntime(dependencies: dependencies, library: library)
    }

    var isEnabled: Bool { runtime.userEnabled && (availability ?? .available) == .available }
    var isDemo: Bool { runtime.demoActive }

    func load() async {
        availability = await runtime.service.availability()
    }

    func explain() async {
        if availability == nil { await load() }
        guard isEnabled, !result.isLoading else { return }
        let code = snippet
        do {
            _ = try AIPrompts.code(code)
        } catch {
            result = .failed(AIRuntime.message(for: error))
            return
        }
        result = .loading
        let task = Task { await self.perform(code) }
        running = task
        await task.value
    }

    func cancel() {
        running?.cancel()
    }

    private func perform(_ code: String) async {
        let service = runtime.service
        do {
            let explanation = try await runtime.run(key: "\(article?.id ?? "standalone")|code") {
                try await service.explainCode(code)
            }
            let id = UUID()
            let artifact = AIArtifact(id: id, kind: .codeExplanation, cacheKey: AICacheKey.codeExplanation(id: id),
                                      articleID: article?.id, articleTitle: article?.title, summaryType: nil, basis: nil,
                                      provider: service.providerInfo, promptVersion: AIPrompts.version, text: nil,
                                      code: explanation, diagram: nil, createdAt: runtime.dependencies.dateProvider.now)
            try await runtime.dependencies.aiLibrary.saveArtifact(artifact)
            result = .loaded(artifact)
        } catch is CancellationError {
            result = .idle
        } catch {
            result = .failed(AIRuntime.message(for: error))
        }
    }
}
