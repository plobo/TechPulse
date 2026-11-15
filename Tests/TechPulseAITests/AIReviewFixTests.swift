import Foundation
import Testing
@testable import TechPulseAI

/// Non-demo, available service that records the history it receives.
final class RecordingAIService: AIService, @unchecked Sendable {
    private let lock = NSLock()
    private var _histories: [[AIMessage]] = []
    var histories: [[AIMessage]] { lock.withLock { _histories } }
    var providerInfo: AIProviderInfo { AIProviderInfo(provider: "Recorder", model: "rec", isDemo: false) }
    func availability() async -> AIAvailability { .available }
    func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String { "real summary" }
    func answer(_ q: String, input: AIArticleInput, history: [AIMessage]) async throws -> String {
        lock.withLock { _histories.append(history) }
        return "real answer"
    }
    func explainCode(_ s: String) async throws -> CodeExplanation { CodeExplanation(language: "x", explanation: "x", risks: []) }
    func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram { try await DemoAIService().diagram(for: input) }
}

/// Throws contextTooLarge when the input is longer than `limit`.
struct SmallContextAIService: AIService {
    let limit: Int
    var providerInfo: AIProviderInfo { AIProviderInfo(provider: "Small", model: "small", isDemo: true) }
    func availability() async -> AIAvailability { .available }
    func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String {
        guard input.text.count <= limit else { throw AIServiceError.contextTooLarge }
        return "fits"
    }
    func answer(_ q: String, input: AIArticleInput, history: [AIMessage]) async throws -> String {
        guard input.text.count <= limit else { throw AIServiceError.contextTooLarge }
        return "fits"
    }
    func explainCode(_ s: String) async throws -> CodeExplanation { CodeExplanation(language: "x", explanation: "x", risks: []) }
    func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram {
        guard input.text.count <= limit else { throw AIServiceError.contextTooLarge }
        return try await DemoAIService().diagram(for: input)
    }
}

@MainActor
@Suite("AI final review fixes", .serialized)
struct AIReviewFixTests {
    let article = makeArticle(availability: .excerptOnly)

    func setup(_ demo: any AIService, real: any AIService = UnavailableAIService(), demoOn: Bool = true) async throws -> (AppDependencies, LibraryStore) {
        let deps = try AppDependencies.test(ai: AIServices(real: real, demo: demo))
        let library = LibraryStore(repository: deps.library)
        await library.updatePreferences {
            $0.aiFeaturesEnabled = true
            $0.demoAIEnabled = demoOn
        }
        return (deps, library)
    }

    // I1
    @Test func cancelledAskPersistsNothingAndReleasesGate() async throws {
        let (deps, library) = try await setup(DemoAIService(delay: .milliseconds(400)))
        let vm = AskArticleViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        vm.draft = "Q?"
        let running = Task { await vm.send() }
        try await Task.sleep(for: .milliseconds(100))
        vm.cancel()
        await running.value
        #expect(vm.conversation.messages.isEmpty)
        #expect(!vm.isAnswering)
        #expect(try await deps.aiLibrary.recentAIActivity(limit: 5).isEmpty)
        vm.draft = "Q again?"
        await vm.send()
        #expect(vm.conversation.messages.count == 2)
    }

    @Test func cancelledDiagramPersistsNothingAndReleasesGate() async throws {
        let (deps, library) = try await setup(DemoAIService(delay: .milliseconds(400)))
        let vm = DiagramViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        let running = Task { await vm.generate() }
        try await Task.sleep(for: .milliseconds(100))
        vm.cancel()
        await running.value
        #expect(vm.state.value == nil && !vm.state.isLoading)
        #expect(try await deps.aiLibrary.recentAIActivity(limit: 5).isEmpty)
        await vm.generate()
        #expect(vm.state.value != nil)
    }

    @Test func cancelledCodeExplanationPersistsNothingAndReleasesGate() async throws {
        let (deps, library) = try await setup(DemoAIService(delay: .milliseconds(400)))
        let vm = CodeExplainerViewModel(article: nil, dependencies: deps, library: library)
        vm.snippet = "let x = 1"
        let running = Task { await vm.explain() }
        try await Task.sleep(for: .milliseconds(100))
        vm.cancel()
        await running.value
        #expect(vm.result.value == nil && !vm.result.isLoading)
        #expect(try await deps.aiLibrary.recentAIActivity(limit: 5).isEmpty)
        await vm.explain()
        #expect(vm.result.value != nil)
    }

    // I2 (focus 5)
    @Test func askAnswersKeepTheirProviderAndDemoHistoryIsNotSentToRealModel() async throws {
        let recorder = RecordingAIService()
        let (deps, library) = try await setup(DemoAIService(), real: recorder)
        let demoVM = AskArticleViewModel(article: article, dependencies: deps, library: library)
        await demoVM.load()
        demoVM.draft = "Demo question?"
        await demoVM.send()
        #expect(demoVM.conversation.messages.last?.provider?.isDemo == true)

        await library.updatePreferences { $0.demoAIEnabled = false }
        let realVM = AskArticleViewModel(article: article, dependencies: deps, library: library)
        await realVM.load()
        #expect(realVM.conversation.messages.contains { $0.provider?.isDemo == true }, "old demo answers keep their demo label")
        realVM.draft = "Real question?"
        await realVM.send()
        let sentHistory = try #require(recorder.histories.last)
        #expect(sentHistory.isEmpty, "demo turns must not be sent to the real model")
        #expect(realVM.conversation.messages.last?.provider?.isDemo == false)
    }

    @Test func oldMessagesWithoutProviderStillDecode() throws {
        let json = Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","role":"assistant","content":"hi","timestamp":"2026-11-14T12:00:00Z"}"#.utf8)
        let message = try JSONDecoder.techPulse.decode(AIMessage.self, from: json)
        #expect(message.provider == nil)
    }

    // M2 (promoted)
    @Test func switchingLengthWhileLoadingDoesNotReportBusy() async throws {
        let (deps, library) = try await setup(DemoAIService(delay: .milliseconds(300)))
        let vm = ArticleAIViewModel(article: article, dependencies: deps, library: library)
        await vm.load()
        let first = Task { await vm.generate(.twoMinutes) }
        try await Task.sleep(for: .milliseconds(50))
        await vm.generate(.thirtySeconds)
        await first.value
        #expect(vm.summaries[.thirtySeconds]?.value != nil)
        #expect(vm.summaries[.thirtySeconds]?.errorMessage == nil)
    }

    // M3 (promoted)
    @Test func publisherSummaryIsCappedSoInputFitsBudget() {
        let long = makeArticle(availability: .excerptOnly, summary: String(repeating: "s", count: 5000))
        let input = AIArticleInput.make(from: long, budget: 2000)
        #expect(input.text.count <= 2000 + 20)
        #expect(input.text.contains("An excerpt."))
    }

    @Test func contextOverflowRetriesOnceWithSmallerInput() async throws {
        let body = Array(repeating: "word", count: 3000).joined(separator: " ")
        let full = makeArticle(availability: .full, content: body)
        let fullLength = AIArticleInput.make(from: full).text.count
        let (deps, library) = try await setup(SmallContextAIService(limit: fullLength - 100))
        let vm = ArticleAIViewModel(article: full, dependencies: deps, library: library)
        await vm.load()
        await vm.generate(.detailed)
        #expect(vm.summaries[.detailed]?.value?.text == "fits")
        let reopened = ArticleAIViewModel(article: full, dependencies: deps, library: library)
        await reopened.load()
        #expect(reopened.summaries[.detailed]?.value != nil, "cached under the article's normal key")
    }

    // M4 (promoted)
    @Test func mermaidNodeIDsCannotCollideWithKeywords() throws {
        let d = try DiagramValidator.validate(ArchitectureDiagram(title: "t", components: [
            .init(id: "end", name: "End", kind: "k", detail: ""), .init(id: "graph", name: "G", kind: "k", detail: ""),
        ], connections: [.init(from: "end", to: "graph", label: "x")]))
        let src = MermaidGenerator.source(for: d)
        #expect(src.contains("n_end[\"End\"]"))
        #expect(src.contains("n_end -->|\"x\"| n_graph"))
        #expect(!src.contains("\n    end["))
    }

    @Test func cyclicDiagramPassesValidation() {
        let d = ArchitectureDiagram(title: "t", components: ["a", "b", "c"].map { .init(id: $0, name: $0, kind: "k", detail: "") },
                                    connections: [.init(from: "a", to: "b", label: ""), .init(from: "b", to: "c", label: ""),
                                                  .init(from: "c", to: "a", label: "")])
        #expect(throws: Never.self) { try DiagramValidator.validate(d) }
    }
}
