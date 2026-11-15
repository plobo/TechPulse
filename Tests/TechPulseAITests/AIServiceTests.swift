import Foundation
import Testing
@testable import TechPulseAI

final class MutableClock: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }
}

@Suite("AI service, gate and demo")
struct AIServiceTests {
    let input = AIArticleInput.make(from: makeArticle(availability: .excerptOnly))

    @Test func gateRejectsConcurrentSameKeyAndAllowsAfterEnd() async throws {
        let gate = AIRequestGate(maxPerMinute: 10, dateProvider: FixedDateProvider(now: TestData.now))
        try await gate.begin("a|summary")
        await #expect(throws: AIServiceError.busy) { try await gate.begin("a|summary") }
        try await gate.begin("b|summary")
        await gate.end("a|summary")
        try await gate.begin("a|summary")
    }

    @Test func gateRateLimitsWithinSixtySeconds() async throws {
        let clock = MutableClock(TestData.now)
        let gate = AIRequestGate(maxPerMinute: 2, dateProvider: clock)
        try await gate.begin("1"); await gate.end("1")
        try await gate.begin("2"); await gate.end("2")
        await #expect(throws: AIServiceError.rateLimited) { try await gate.begin("3") }
        clock.advance(61)
        try await gate.begin("3")
    }

    @Test func servicesPickDemoOnlyWhenEnabledAndPresent() {
        let services = AIServices(real: UnavailableAIService(), demo: DemoAIService())
        #expect(services.active(demoEnabled: true).providerInfo.isDemo)
        #expect(!services.active(demoEnabled: false).providerInfo.isDemo)
        #expect(!AIServices(real: UnavailableAIService(), demo: nil).active(demoEnabled: true).providerInfo.isDemo)
    }

    @Test func demoOutputIsMarkedFake() async throws {
        let demo = DemoAIService()
        #expect(await demo.availability() == .available)
        #expect(try await demo.summarize(input, type: .twoMinutes).hasPrefix("[Demo AI — fake output] "))
        #expect(try await demo.answer("Why?", input: input, history: []).hasPrefix("[Demo AI — fake output] "))
        let code = try await demo.explainCode("let x = 1")
        #expect(code.explanation.hasPrefix("[Demo AI — fake output] "))
        #expect(!code.language.isEmpty)
        #expect(CodeExplanation.caveat == "AI explanations can be wrong and are not a security review.")
    }

    @Test func demoDiagramIsValid() async throws {
        let raw = try await DemoAIService().diagram(for: input)
        #expect(throws: Never.self) { try DiagramValidator.validate(raw) }
    }

    @Test func unavailableServiceThrowsUnavailable() async {
        let service = UnavailableAIService(reason: .deviceNotEligible)
        #expect(await service.availability() == .deviceNotEligible)
        await #expect(throws: AIServiceError.unavailable) { try await service.summarize(input, type: .detailed) }
        #expect(!AIAvailability.appleIntelligenceNotEnabled.message.isEmpty)
    }

    @Test func oldPreferencesPayloadStillDecodes() throws {
        let old = Data(#"{"selectedCategoryIDs":["coding"],"followedTechnologies":[],"preferredSummaryLength":"detailed","theme":"dark","notifications":{"digestEnabled":false,"topicAlertsEnabled":false,"quietHoursStart":22,"quietHoursEnd":7},"aiFeaturesEnabled":true,"personalizationEnabled":true,"hasCompletedOnboarding":false}"#.utf8)
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: old)
        #expect(prefs.selectedCategoryIDs == ["coding"] && prefs.theme == .dark && prefs.aiFeaturesEnabled)
        #expect(prefs.demoAIEnabled == false)
        #expect(prefs.aiGenerationCount == 0)
    }

    @Test func demoForcedOnlyUnderUITesting() {
        #expect(AppConfiguration(values: [:], arguments: ["-ui-testing", "-demo-ai"]).forcesDemoAI)
        #expect(!AppConfiguration(values: [:], arguments: ["-demo-ai"]).forcesDemoAI)
    }
}
