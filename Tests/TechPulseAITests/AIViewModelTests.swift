import Foundation
import Testing
@testable import TechPulseAI

/// Wraps the demo service and counts model calls.
struct CountingAIService: AIService {
    let counter = CallFlag()
    var inner = DemoAIService()
    var providerInfo: AIProviderInfo { inner.providerInfo }
    func availability() async -> AIAvailability { .available }
    func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String {
        counter.hit(); return try await inner.summarize(input, type: type)
    }
    func answer(_ q: String, input: AIArticleInput, history: [AIMessage]) async throws -> String {
        counter.hit(); return try await inner.answer(q, input: input, history: history)
    }
    func explainCode(_ s: String) async throws -> CodeExplanation { counter.hit(); return try await inner.explainCode(s) }
    func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram { counter.hit(); return try await inner.diagram(for: input) }
}

/// Returns a diagram with a self-loop.
struct BadDiagramAIService: AIService {
    var providerInfo: AIProviderInfo { AIProviderInfo(provider: "Bad", model: "bad", isDemo: true) }
    func availability() async -> AIAvailability { .available }
    func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String { "x" }
    func answer(_ q: String, input: AIArticleInput, history: [AIMessage]) async throws -> String { "x" }
    func explainCode(_ s: String) async throws -> CodeExplanation { CodeExplanation(language: "x", explanation: "x", risks: []) }
    func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram {
        ArchitectureDiagram(title: "t", components: [.init(id: "a", name: "A", kind: "k", detail: "")],
                            connections: [.init(from: "a", to: "a", label: "loop")])
    }
}

@MainActor
@Suite("AI view models", .serialized)
struct AIViewModelTests {
    let article = makeArticle(availability: .excerptOnly)

    func setup(_ service: any AIService = DemoAIService(), enabled: Bool = true) async throws -> (AppDependencies, LibraryStore) {
        let deps = try AppDependencies.test(ai: AIServices(real: UnavailableAIService(), demo: service))
        let library = LibraryStore(repository: deps.library)
        await library.updatePreferences {
            $0.aiFeaturesEnabled = enabled
            $0.demoAIEnabled = true
        }
        return (deps, library)
    }

    @Test func summaryUsesCacheOnSecondLoad() async throws {
        let counting = CountingAIService()
        let (deps, library) = try await setup(counting)
        let vm = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        await vm.generate(.twoMinutes)
        #expect(vm.summaries[.twoMinutes]?.value?.text?.hasPrefix(DemoAIService.marker) == true)
        let second = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await second.load()
        #expect(second.summaries[.twoMinutes]?.value != nil)
        #expect(counting.counter.count == 1)
    }

    @Test func summaryLabelsBasisForExcerptArticle() async throws {
        let (deps, library) = try await setup()
        let vm = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        await vm.generate(.thirtySeconds)
        #expect(vm.summaries[.thirtySeconds]?.value?.basis == .excerptOnly)
        #expect(vm.summaries[.thirtySeconds]?.value?.provider.isDemo == true)
        #expect(vm.isDemo)
    }

    @Test func regenerateReplacesCachedSummary() async throws {
        let counting = CountingAIService()
        let (deps, library) = try await setup(counting)
        let vm = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        await vm.generate(.detailed)
        let first = try #require(vm.summaries[.detailed]?.value)
        await vm.generate(.detailed)
        #expect(counting.counter.count == 1, "cached result reused without force")
        await vm.generate(.detailed, force: true)
        #expect(counting.counter.count == 2)
        #expect(vm.summaries[.detailed]?.value?.id != first.id)
    }

    @Test func cancelledSummaryPersistsNothingAndReleasesGate() async throws {
        let (deps, library) = try await setup(DemoAIService(delay: .milliseconds(400)))
        let vm = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        let running = Task { await vm.generate(.detailed) }
        try await Task.sleep(for: .milliseconds(100))
        vm.cancel()
        await running.value
        #expect(vm.summaries[.detailed]?.value == nil)
        #expect(try await deps.aiLibrary.recentAIActivity(limit: 10).isEmpty)
        await vm.generate(.detailed)
        #expect(vm.summaries[.detailed]?.value != nil)
    }

    @Test func disabledOrUnavailableBlocksGeneration() async throws {
        let counting = CountingAIService()
        let (deps, library) = try await setup(counting, enabled: false)
        let vm = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        #expect(!vm.isEnabled)
        await vm.generate(.twoMinutes)
        #expect(counting.counter.count == 0)

        let deps2 = try AppDependencies.test()
        let lib2 = LibraryStore(repository: deps2.library)
        await lib2.updatePreferences { $0.aiFeaturesEnabled = true }
        let vm2 = ArticleAIViewModel(article: article, dependencies: deps2, library: lib2)
        await vm2.load()
        #expect(vm2.availability == .unsupportedOS)
        #expect(!vm2.isEnabled)
    }

    @Test func askPersistsConversationAndResumes() async throws {
        let (deps, library) = try await setup()
        let vm = AskArticleViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        vm.draft = "What is this about?"
        await vm.send()
        #expect(vm.conversation.messages.count == 2)
        #expect(vm.draft.isEmpty)
        let resumed = AskArticleViewModel(article: article, dependencies: deps, library: library)
        await resumed.load()
        #expect(resumed.conversation.messages.map(\.role) == [.user, .assistant])
    }

    @Test func askRejectsOverlongQuestionWithMessage() async throws {
        let counting = CountingAIService()
        let (deps, library) = try await setup(counting)
        let vm = AskArticleViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        vm.draft = String(repeating: "q", count: 501)
        await vm.send()
        #expect(vm.error == AIServiceError.requestTooLarge.message)
        #expect(counting.counter.count == 0)
        #expect(vm.conversation.messages.isEmpty)
    }

    @Test func codeExplanationSavedWithCaveatAvailable() async throws {
        let (deps, library) = try await setup()
        let vm = CodeExplainerViewModel(article: nil, dependencies: deps, library: library)
        vm.snippet = "let x = 1"
        await vm.explain()
        let artifact = try #require(vm.result.value)
        #expect(artifact.kind == .codeExplanation && artifact.code != nil && artifact.articleID == nil)
        #expect(try await deps.aiLibrary.recentAIActivity(limit: 5).count == 1)
    }

    @Test func invalidDiagramIsRejectedNotSaved() async throws {
        let (deps, library) = try await setup(BadDiagramAIService())
        let vm = DiagramViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        await vm.generate()
        #expect(vm.state.value == nil)
        #expect(vm.state.errorMessage?.contains("self-connection") == true)
        #expect(try await deps.aiLibrary.recentAIActivity(limit: 5).isEmpty)
    }

    @Test func validDiagramIsSavedAndCached() async throws {
        let counting = CountingAIService()
        let (deps, library) = try await setup(counting)
        let vm = DiagramViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        await vm.generate()
        #expect(vm.state.value?.diagram?.components.count == 4)
        let again = DiagramViewModel(article: article, dependencies: deps, library: library)
        await again.load()
        #expect(again.state.value != nil)
        #expect(counting.counter.count == 1)
    }

    @Test func aiReaderListsAndClearsActivity() async throws {
        let (deps, library) = try await setup()
        let summaries = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await summaries.load()
        await summaries.generate(.twoMinutes)
        let ask = AskArticleViewModel(article: article, dependencies: deps, library: library)
        await ask.load()
        ask.draft = "Q?"
        await ask.send()
        let reader = AIReaderViewModel(dependencies: deps, library: library)
        await reader.load()
        #expect(reader.items.count == 2)
        #expect(reader.isEnabled)
        await reader.delete(reader.items[0])
        #expect(reader.items.count == 1)
        await reader.clearAll()
        #expect(reader.items.isEmpty)
    }

    @Test func generationCountIncrements() async throws {
        let (deps, library) = try await setup()
        let vm = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        await vm.generate(.thirtySeconds)
        await vm.generate(.twoMinutes)
        #expect(library.preferences.aiGenerationCount == 2)
    }

    @Test func reportTextIncludesProvenanceButNoNotes() async throws {
        let (deps, library) = try await setup()
        try await library.saveNote(articleID: article.id, text: "PRIVATE NOTE")
        let vm = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        await vm.generate(.twoMinutes)
        let artifact = try #require(vm.summaries[.twoMinutes]?.value)
        let report = AIReport.text(for: artifact)
        #expect(report.contains(article.id) && report.contains("Demo AI") && report.contains(AIPrompts.version))
        #expect(report.contains("Based on the excerpt only"))
        #expect(!report.contains("PRIVATE NOTE"))
    }

    @Test func settingsShowsAvailabilityAndClearsAIHistory() async throws {
        let (deps, library) = try await setup()
        let vm = SettingsViewModel(library: library, notifications: StubNotificationAuthorizer(grant: true),
                                   aiServices: deps.ai, aiLibrary: deps.aiLibrary)
        await vm.loadAIAvailability()
        #expect(vm.aiAvailability == .available)
        await vm.setDemoAI(false)
        await vm.loadAIAvailability()
        #expect(vm.aiAvailability == .unsupportedOS)
        let summaries = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await summaries.load()
        await vm.clearAIHistory()
        #expect(try await deps.aiLibrary.recentAIActivity(limit: 5).isEmpty)
    }
}
