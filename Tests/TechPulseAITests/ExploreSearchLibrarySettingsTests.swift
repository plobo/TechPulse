import Foundation
import Testing
@testable import TechPulseAI

actor StubNotificationAuthorizer: NotificationAuthorizing {
    let grant: Bool
    private(set) var requests = 0
    init(grant: Bool) { self.grant = grant }
    func requestAuthorization() async -> Bool {
        requests += 1
        return grant
    }
}

@MainActor
@Suite("Explore, search, library and settings")
struct ExploreSearchLibrarySettingsTests {
    let ai = TestData.article(id: "ai", publishedAt: TestData.now.addingTimeInterval(-3600), categoryIDs: ["ai-ml"], tags: ["llm"])
    let code = TestData.article(id: "code", publishedAt: TestData.now.addingTimeInterval(-10 * 86_400), categoryIDs: ["coding"], tags: ["swift"])

    // MARK: Explore

    @Test func exploreLoadsCategoriesSourcesAndTrendingTags() async throws {
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: [ai, code], nextCursor: nil))])
        let vm = ExploreViewModel(dependencies: try .test(content: content))
        await vm.load()
        #expect(vm.categories.count == 8)
        #expect(vm.sources.map(\.id) == ["src"])
        #expect(Set(vm.trendingTags) == ["llm", "swift"])
    }

    @Test func articleListFiltersByCategoryDifficultyAndDate() async throws {
        let adv = Article(id: "adv", canonicalURL: URL(string: "https://example.com/adv")!, title: "Adv", summary: nil, excerpt: nil,
                          content: nil, imageURL: nil, sourceID: "src", sourceName: "Source", author: nil,
                          publishedAt: TestData.now, fetchedAt: TestData.now, categoryIDs: ["ai-ml"], tags: [],
                          readingTimeMinutes: nil, contentAvailability: .linkOnly, difficulty: .advanced)
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: [ai, adv, code], nextCursor: nil))])
        let vm = ArticleListViewModel(kind: .category("ai-ml"), dependencies: try .test(content: content))
        await vm.load()
        #expect(vm.title == "AI & Machine Learning")
        #expect(vm.visibleItems.map(\.article.id) == ["ai", "adv"])
        vm.difficulty = .advanced
        #expect(vm.visibleItems.map(\.article.id) == ["adv"])
        vm.difficulty = nil
        let sourceVM = ArticleListViewModel(kind: .source("src"), dependencies: try .test(content: content))
        await sourceVM.load()
        sourceVM.dateRange = .week
        #expect(!sourceVM.visibleItems.contains { $0.article.id == "code" })
    }

    @Test func dateRangeFilterComputesLowerBound() {
        #expect(DateRangeFilter.any.lowerBound(now: TestData.now) == nil)
        #expect(DateRangeFilter.day.lowerBound(now: TestData.now) == TestData.now.addingTimeInterval(-86_400))
        #expect(DateRangeFilter.month.lowerBound(now: TestData.now) == TestData.now.addingTimeInterval(-30 * 86_400))
    }

    // MARK: Search

    @Test func blankSearchDoesNotHitRepository() async throws {
        let content = StubContentRepository()
        let vm = SearchViewModel(dependencies: try .test(content: content))
        vm.query = "   "
        await vm.search()
        #expect(await content.searchLog.isEmpty)
        if case .idle = vm.results {} else { Issue.record("expected idle") }
    }

    @Test func searchPassesFiltersAndSort() async throws {
        let content = StubContentRepository()
        await content.setSearchResults([ai])
        let vm = SearchViewModel(dependencies: try .test(content: content))
        vm.query = "llm"
        vm.categoryID = "ai-ml"
        vm.sourceID = "src"
        vm.sort = .newest
        vm.dateRange = .week
        vm.difficulty = .beginner
        await vm.search()
        let sent = try #require(await content.searchLog.last)
        #expect(sent.text == "llm" && sent.categoryID == "ai-ml" && sent.sourceID == "src" && sent.sort == .newest)
        #expect(sent.from == TestData.now.addingTimeInterval(-7 * 86_400))
        #expect(sent.difficulty == .beginner)
        #expect(vm.results.value?.map(\.id) == ["ai"])
    }

    @Test func searchWithNoMatchesIsEmptyState() async throws {
        let vm = SearchViewModel(dependencies: try .test())
        vm.query = "nothing"
        await vm.search()
        #expect(vm.results.isEmpty)
    }

    // MARK: Library

    @Test func libraryListsBookmarksWithReadAndCategoryFilters() async throws {
        let deps = try AppDependencies.test()
        let store = LibraryStore(repository: deps.library)
        await store.toggleBookmark(ai)
        await store.toggleBookmark(code)
        await store.recordOpen(code)
        let vm = LibraryViewModel(dependencies: deps, library: store)
        await vm.load()
        #expect(vm.section == .bookmarks)
        #expect(Set(vm.visibleArticles.map(\.id)) == ["ai", "code"])
        vm.readFilter = .unread
        #expect(vm.visibleArticles.map(\.id) == ["ai"])
        vm.readFilter = .read
        #expect(vm.visibleArticles.map(\.id) == ["code"])
        vm.readFilter = .all
        vm.categoryID = "coding"
        #expect(vm.visibleArticles.map(\.id) == ["code"])
    }

    @Test func libraryHistoryAndNotesSectionsAndRemoval() async throws {
        let deps = try AppDependencies.test()
        let store = LibraryStore(repository: deps.library)
        await store.recordOpen(ai)
        try await store.saveNote(articleID: "ai", text: "note on ai")
        let vm = LibraryViewModel(dependencies: deps, library: store)
        vm.section = .history
        await vm.load()
        #expect(vm.visibleArticles.map(\.id) == ["ai"])
        vm.section = .notes
        await vm.load()
        #expect(vm.notes.map(\.note.text) == ["note on ai"])
        #expect(vm.notes.first?.article?.title == ai.title)
        await vm.clearHistory()
        vm.section = .history
        await vm.load()
        #expect(vm.visibleArticles.isEmpty)
    }

    @Test func libraryRemoveBookmark() async throws {
        let deps = try AppDependencies.test()
        let store = LibraryStore(repository: deps.library)
        await store.toggleBookmark(ai)
        let vm = LibraryViewModel(dependencies: deps, library: store)
        await vm.load()
        await vm.removeBookmark(ai.id)
        #expect(vm.visibleArticles.isEmpty)
        #expect(!store.isBookmarked(ai.id))
    }

    // MARK: Settings

    @Test func settingsUpdatesAndPersistsPreferences() async throws {
        let deps = try AppDependencies.test()
        let store = LibraryStore(repository: deps.library)
        let vm = SettingsViewModel(library: store, notifications: StubNotificationAuthorizer(grant: true))
        await vm.toggleCategory("coding")
        await vm.addTechnology("  SwiftUI ")
        await vm.addTechnology("swiftui")
        await vm.setTheme(.dark)
        #expect(store.preferences.selectedCategoryIDs == ["coding"])
        #expect(store.preferences.followedTechnologies == ["SwiftUI"])
        let persisted = try await deps.library.preferences()
        #expect(persisted.theme == .dark && persisted.selectedCategoryIDs == ["coding"])
        await vm.toggleCategory("coding")
        #expect(store.preferences.selectedCategoryIDs.isEmpty)
        await vm.removeTechnology("SwiftUI")
        #expect(store.preferences.followedTechnologies.isEmpty)
    }

    @Test func enablingDigestAsksPermissionContextuallyAndRevertsOnDenial() async throws {
        let deps = try AppDependencies.test()
        let store = LibraryStore(repository: deps.library)
        let denied = StubNotificationAuthorizer(grant: false)
        let vm = SettingsViewModel(library: store, notifications: denied)
        #expect(await denied.requests == 0, "no prompt on launch")
        await vm.setDigestEnabled(true)
        #expect(await denied.requests == 1)
        #expect(store.preferences.notifications.digestEnabled == false)
        #expect(vm.notificationMessage != nil)
        let granted = SettingsViewModel(library: store, notifications: StubNotificationAuthorizer(grant: true))
        await granted.setDigestEnabled(true)
        #expect(store.preferences.notifications.digestEnabled)
    }

    @Test func exportWritesJSONFileAndDeleteAllResets() async throws {
        let deps = try AppDependencies.test()
        let store = LibraryStore(repository: deps.library)
        await store.toggleBookmark(ai)
        let vm = SettingsViewModel(library: store, notifications: StubNotificationAuthorizer(grant: true))
        let url = try #require(await vm.exportData())
        #expect(url.pathExtension == "json")
        let export = try JSONDecoder.techPulse.decode(LibraryExport.self, from: Data(contentsOf: url))
        #expect(export.bookmarks.map(\.articleID) == ["ai"])
        await vm.deleteAllData()
        #expect(store.bookmarkedIDs.isEmpty)
    }

    @Test func formattingHelpers() {
        #expect(ArticleFormatting.readingTime(4) == "4 min read")
        #expect(ArticleFormatting.readingTime(nil) == nil)
        let label = ArticleFormatting.accessibilityLabel(for: ai, now: TestData.now, isBookmarked: true, isRead: false)
        #expect(label.contains("Title") && label.contains("from Source") && label.contains("Bookmarked") && label.contains("Unread"))
    }
}
