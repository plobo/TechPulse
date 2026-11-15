import Foundation
import Observation

@MainActor
@Observable
final class DiagramViewModel {
    let article: Article
    let input: AIArticleInput
    private(set) var state: AIOutputState<AIArtifact> = .idle
    private(set) var availability: AIAvailability?
    private let runtime: AIRuntime

    init(article: Article, dependencies: AppDependencies, library: LibraryStore) {
        self.article = article
        self.input = AIArticleInput.make(from: article)
        self.runtime = AIRuntime(dependencies: dependencies, library: library)
    }

    var isEnabled: Bool { runtime.userEnabled && availability == .available }
    var isDemo: Bool { runtime.demoActive }
    var isSampleData: Bool { runtime.dependencies.isSampleData }

    func load() async {
        availability = await runtime.service.availability()
        let key = AICacheKey.diagram(input, provider: runtime.service.providerInfo)
        if let cached = try? await runtime.dependencies.aiLibrary.artifact(cacheKey: key) {
            state = .loaded(cached)
        }
    }

    func generate(force: Bool = false) async {
        guard isEnabled, !state.isLoading else { return }
        if !force, state.value != nil { return }
        let previous = state
        state = .loading
        let service = runtime.service
        let input = input
        do {
            let diagram = try await runtime.run(key: "\(article.id)|diagram") {
                try DiagramValidator.validate(try await service.diagram(for: input))
            }
            let artifact = AIArtifact(id: UUID(), kind: .diagram, cacheKey: AICacheKey.diagram(input, provider: service.providerInfo),
                                      articleID: article.id, articleTitle: article.title, summaryType: nil, basis: input.basis,
                                      provider: service.providerInfo, promptVersion: AIPrompts.version, text: nil,
                                      code: nil, diagram: diagram, createdAt: runtime.dependencies.dateProvider.now)
            try await runtime.dependencies.aiLibrary.saveArtifact(artifact)
            state = .loaded(artifact)
        } catch is CancellationError {
            state = previous
        } catch {
            state = .failed(AIRuntime.message(for: error))
        }
    }
}
