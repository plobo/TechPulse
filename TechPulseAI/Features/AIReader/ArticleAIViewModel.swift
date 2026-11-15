import Foundation
import Observation

/// Summaries panel on the article page.
@MainActor
@Observable
final class ArticleAIViewModel {
    let article: Article
    let input: AIArticleInput
    var selectedType: SummaryType = .twoMinutes
    private(set) var summaries: [SummaryType: AIOutputState<AIArtifact>] = [:]
    private(set) var availability: AIAvailability?
    private var running: Task<Void, Never>?
    private let runtime: AIRuntime

    init(article: Article, dependencies: AppDependencies, library: LibraryStore) {
        self.article = article
        self.input = AIArticleInput.make(from: article)
        self.runtime = AIRuntime(dependencies: dependencies, library: library)
    }

    var isEnabled: Bool { runtime.userEnabled && availability == .available }
    var isDemo: Bool { runtime.demoActive }
    var isSampleData: Bool { runtime.dependencies.isSampleData }
    var provider: AIProviderInfo { runtime.service.providerInfo }
    var current: AIOutputState<AIArtifact> { summaries[selectedType] ?? .idle }

    func load() async {
        selectedType = SummaryType(runtime.library.preferences.preferredSummaryLength)
        availability = await runtime.service.availability()
        for type in SummaryType.allCases {
            let key = AICacheKey.summary(input, type: type, provider: provider)
            if let cached = try? await runtime.dependencies.aiLibrary.artifact(cacheKey: key) {
                summaries[type] = .loaded(cached)
            }
        }
    }

    func generate(_ type: SummaryType, force: Bool = false) async {
        guard isEnabled else { return }
        if !force, summaries[type]?.value != nil { return }
        running?.cancel()
        let previous = summaries[type] ?? .idle
        summaries[type] = .loading
        let task = Task { await self.perform(type, previous: previous) }
        running = task
        await task.value
    }

    func cancel() {
        running?.cancel()
    }

    private func perform(_ type: SummaryType, previous: AIOutputState<AIArtifact>) async {
        let service = runtime.service
        let input = input
        do {
            let text = try await runtime.run(key: "\(article.id)|summary") {
                try await service.summarize(input, type: type)
            }
            let artifact = AIArtifact(id: UUID(), kind: .summary, cacheKey: AICacheKey.summary(input, type: type, provider: service.providerInfo),
                                      articleID: article.id, articleTitle: article.title, summaryType: type, basis: input.basis,
                                      provider: service.providerInfo, promptVersion: AIPrompts.version, text: text,
                                      code: nil, diagram: nil, createdAt: runtime.dependencies.dateProvider.now)
            try await runtime.dependencies.aiLibrary.saveArtifact(artifact)
            summaries[type] = .loaded(artifact)
        } catch is CancellationError {
            summaries[type] = previous.isLoading ? .idle : previous
        } catch {
            summaries[type] = .failed(AIRuntime.message(for: error))
        }
    }
}
