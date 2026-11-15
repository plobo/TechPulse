import Foundation
import SwiftData
import Testing
@testable import TechPulseAI

@Suite("AI persistence and V2 migration", .serialized)
struct AIPersistenceTests {
    let real = AIProviderInfo(provider: "Apple Foundation Models", model: "SystemLanguageModel.default", isDemo: false)
    let demo = AIProviderInfo(provider: "Demo AI", model: "demo", isDemo: true)

    func repo(at url: URL? = nil, now: Date = TestData.now) throws -> SwiftDataLibraryRepository {
        let container = try PersistenceController.makeContainer(storeURL: url, inMemory: url == nil)
        return SwiftDataLibraryRepository(modelContainer: container, dateProvider: FixedDateProvider(now: now))
    }

    func summary(_ articleID: String = "a1", key: String = "k1", at date: Date = TestData.now, text: String = "S") -> AIArtifact {
        AIArtifact(id: UUID(), kind: .summary, cacheKey: key, articleID: articleID, articleTitle: "Title",
                   summaryType: .twoMinutes, basis: .excerptOnly, provider: real, promptVersion: AIPrompts.version,
                   text: text, code: nil, diagram: nil, createdAt: date)
    }

    func conversation(_ articleID: String = "a1", at date: Date = TestData.now) -> AIConversation {
        AIConversation(id: UUID(), articleID: articleID, articleTitle: "Title", basis: .excerptOnly,
                       messages: [AIMessage(id: UUID(), role: .user, content: "Q?", timestamp: date)], updatedAt: date)
    }

    @Test func v1StoreMigratesToV2KeepingUserData() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v1-\(UUID().uuidString).store")
        do {
            let schema = Schema(versionedSchema: TechPulseSchemaV1.self)
            let v1 = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(v1)
            context.insert(BookmarkRecord(articleID: "kept", createdAt: TestData.now))
            context.insert(NoteRecord(noteID: UUID(), articleID: "kept", text: "old note", createdAt: TestData.now))
            try context.save()
        }
        let migrated = try repo(at: url)
        #expect(try await migrated.bookmarks().map(\.articleID) == ["kept"])
        #expect(try await migrated.allNotes().map(\.text) == ["old note"])
        #expect(try await migrated.recentAIActivity(limit: 10).isEmpty)
        #expect(TechPulseMigrationPlan.schemas.count == 2)
    }

    @Test func artifactUpsertAndLookupByCacheKey() async throws {
        let r = try repo()
        try await r.saveArtifact(summary(text: "first"))
        try await r.saveArtifact(summary(text: "second"))
        #expect(try await r.artifact(cacheKey: "k1")?.text == "second")
        #expect(try await r.recentAIActivity(limit: 10).count == 1)
        #expect(try await r.artifact(cacheKey: "missing") == nil)
    }

    @Test func conversationSaveAndResumeByArticle() async throws {
        let r = try repo()
        var c = conversation()
        try await r.saveConversation(c)
        c.messages.append(AIMessage(id: UUID(), role: .assistant, content: "A.", timestamp: TestData.now))
        try await r.saveConversation(c)
        let resumed = try await r.conversation(articleID: "a1")
        #expect(resumed?.id == c.id)
        #expect(resumed?.messages.count == 2)
        #expect(try await r.conversation(articleID: "other") == nil)
    }

    @Test func recentActivityNewestFirstAcrossKinds() async throws {
        let r = try repo()
        try await r.saveArtifact(summary(key: "old", at: TestData.now.addingTimeInterval(-100)))
        try await r.saveConversation(conversation(at: TestData.now))
        let diagram = AIArtifact(id: UUID(), kind: .diagram, cacheKey: "d", articleID: "a1", articleTitle: "T", summaryType: nil,
                                 basis: .fullText, provider: real, promptVersion: AIPrompts.version, text: nil, code: nil,
                                 diagram: ArchitectureDiagram(title: "x", components: [], connections: []),
                                 createdAt: TestData.now.addingTimeInterval(-50))
        try await r.saveArtifact(diagram)
        let items = try await r.recentAIActivity(limit: 10)
        #expect(items.map(\.date) == items.map(\.date).sorted(by: >))
        guard case .conversation = items.first else { Issue.record("conversation should be first"); return }
        #expect(try await r.recentAIActivity(limit: 2).count == 2)
    }

    @Test func deleteAndClearAIHistory() async throws {
        let r = try repo()
        let s = summary()
        let c = conversation()
        try await r.saveArtifact(s)
        try await r.saveConversation(c)
        try await r.deleteAIItem(id: s.id)
        #expect(try await r.recentAIActivity(limit: 10).count == 1)
        try await r.deleteAIItem(id: c.id)
        #expect(try await r.recentAIActivity(limit: 10).isEmpty)
        try await r.saveArtifact(summary(key: "z"))
        try await r.clearAIHistory()
        #expect(try await r.recentAIActivity(limit: 10).isEmpty)
    }

    @Test func exportIncludesAIAndDeleteAllRemovesIt() async throws {
        let r = try repo()
        try await r.saveArtifact(summary())
        let export = try JSONDecoder.techPulse.decode(LibraryExport.self, from: try await r.exportData())
        #expect(export.ai?.count == 1)
        try await r.deleteAllData()
        #expect(try await r.recentAIActivity(limit: 10).isEmpty)
        let oldExport = Data(#"{"exportedAt":"2026-11-14T12:00:00Z","bookmarks":[],"notes":[],"history":[],"preferences":{}}"#.utf8)
        #expect(try JSONDecoder.techPulse.decode(LibraryExport.self, from: oldExport).ai == nil)
    }

    @Test func clearCacheKeepsAIHistory() async throws {
        let r = try repo()
        try await r.saveArtifact(summary())
        _ = try await r.clearCache()
        #expect(try await r.recentAIActivity(limit: 10).count == 1)
    }

    @Test func cacheKeySeparatesDemoFromRealProvider() {
        let input = AIArticleInput.make(from: makeArticle(availability: .excerptOnly))
        #expect(AICacheKey.summary(input, type: .detailed, provider: real) != AICacheKey.summary(input, type: .detailed, provider: demo))
        #expect(AICacheKey.summary(input, type: .detailed, provider: real) != AICacheKey.summary(input, type: .twoMinutes, provider: real))
        #expect(AICacheKey.summary(input, type: .detailed, provider: real).contains(AIPrompts.version))
        #expect(AICacheKey.diagram(input, provider: real) != AICacheKey.diagram(input, provider: demo))
    }
}
