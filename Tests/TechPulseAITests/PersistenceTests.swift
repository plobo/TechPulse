import Foundation
import SwiftData
import Testing
@testable import TechPulseAI

@Suite("SwiftData library persistence", .serialized)
struct PersistenceTests {
    func makeRepo(url: URL? = nil, now: Date = TestData.now) throws -> SwiftDataLibraryRepository {
        let container = try PersistenceController.makeContainer(storeURL: url, inMemory: url == nil)
        return SwiftDataLibraryRepository(modelContainer: container, dateProvider: FixedDateProvider(now: now))
    }

    func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tp-\(UUID().uuidString).store")
    }

    @Test func toggleBookmarkAddsAndRemoves() async throws {
        let repo = try makeRepo()
        let article = TestData.article(id: "a")
        #expect(try await repo.toggleBookmark(article) == true)
        #expect(try await repo.bookmarks().map(\.articleID) == ["a"])
        #expect(try await repo.toggleBookmark(article) == false)
        #expect(try await repo.bookmarks().isEmpty)
    }

    @Test func bookmarksAndNotesPersistAcrossRelaunch() async throws {
        let url = tempStoreURL()
        do {
            let repo = try makeRepo(url: url)
            _ = try await repo.toggleBookmark(TestData.article(id: "keep", title: "Saved title"))
            _ = try await repo.saveNote(id: nil, articleID: "keep", text: "remember this")
        }
        let reopened = try makeRepo(url: url)
        #expect(try await reopened.bookmarks().map(\.articleID) == ["keep"])
        #expect(try await reopened.cachedArticles(ids: ["keep"]).first?.title == "Saved title", "metadata available offline")
        #expect(try await reopened.notes(for: "keep").map(\.text) == ["remember this"])
    }

    @Test func readingHistoryOrdersByLastOpenedAndCanBeCleared() async throws {
        let earlier = try makeRepo(now: TestData.now)
        try await earlier.recordOpen(TestData.article(id: "1"))
        let container = earlier.modelContainer
        let later = SwiftDataLibraryRepository(modelContainer: container, dateProvider: FixedDateProvider(now: TestData.now.addingTimeInterval(60)))
        try await later.recordOpen(TestData.article(id: "2"))
        #expect(try await later.history().map(\.articleID) == ["2", "1"])
        let evenLater = SwiftDataLibraryRepository(modelContainer: container, dateProvider: FixedDateProvider(now: TestData.now.addingTimeInterval(120)))
        try await evenLater.recordOpen(TestData.article(id: "1"))
        let history = try await evenLater.history()
        #expect(history.map(\.articleID) == ["1", "2"])
        #expect(history.first?.openCount == 2)
        try await evenLater.clearHistory()
        #expect(try await evenLater.history().isEmpty)
    }

    @Test func notesCanBeEditedAndDeleted() async throws {
        let repo = try makeRepo()
        let note = try await repo.saveNote(id: nil, articleID: "a", text: "first")
        let edited = try await repo.saveNote(id: note.id, articleID: "a", text: "edited")
        #expect(edited.id == note.id)
        #expect(try await repo.allNotes().map(\.text) == ["edited"])
        try await repo.deleteNote(id: note.id)
        #expect(try await repo.notes(for: "a").allSatisfy { $0.id != note.id })
    }

    @Test func blankNotesAreRejected() async throws {
        let repo = try makeRepo()
        await #expect(throws: LibraryError.emptyNote) { _ = try await repo.saveNote(id: nil, articleID: "a", text: "  \n ") }
    }

    @Test func clearCacheKeepsArticlesThatAreBookmarkedOrNoted() async throws {
        let repo = try makeRepo()
        _ = try await repo.toggleBookmark(TestData.article(id: "saved"))
        try await repo.recordOpen(TestData.article(id: "noted"))
        _ = try await repo.saveNote(id: nil, articleID: "noted", text: "n")
        try await repo.recordOpen(TestData.article(id: "transient"))
        let removed = try await repo.clearCache()
        #expect(removed == 1)
        #expect(Set(try await repo.cachedArticles(ids: ["saved", "noted", "transient"]).map(\.id)) == ["saved", "noted"])
    }

    @Test func preferencesRoundTripWithDefaults() async throws {
        let repo = try makeRepo()
        #expect(try await repo.preferences() == .default)
        var prefs = UserPreferences.default
        prefs.selectedCategoryIDs = ["coding", "architecture"]
        prefs.followedTechnologies = ["swift"]
        prefs.theme = .dark
        prefs.notifications.digestEnabled = true
        try await repo.savePreferences(prefs)
        #expect(try await repo.preferences() == prefs)
    }

    @Test func exportContainsUserDataAndDeleteAllRemovesIt() async throws {
        let repo = try makeRepo()
        _ = try await repo.toggleBookmark(TestData.article(id: "b"))
        _ = try await repo.saveNote(id: nil, articleID: "b", text: "exported note")
        let data = try await repo.exportData()
        let export = try JSONDecoder.techPulse.decode(LibraryExport.self, from: data)
        #expect(export.bookmarks.map(\.articleID) == ["b"])
        #expect(export.notes.map(\.text) == ["exported note"])
        try await repo.deleteAllData()
        #expect(try await repo.bookmarks().isEmpty)
        #expect(try await repo.allNotes().isEmpty)
        #expect(try await repo.preferences() == .default)
    }

    @Test func migrationPlanStartsAtVersionOne() throws {
        #expect(TechPulseMigrationPlan.schemas.count >= 1)
        #expect(TechPulseSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        let url = tempStoreURL()
        _ = try PersistenceController.makeContainer(storeURL: url, inMemory: false)
        _ = try PersistenceController.makeContainer(storeURL: url, inMemory: false) // reopen with plan
    }
}
