import Foundation
import Testing
@testable import TechPulseAI

@MainActor
@Suite("Discover and article detail view models")
struct DiscoverAndDetailTests {
    let a1 = TestData.article(id: "1", categoryIDs: ["ai-ml"], tags: ["llm"])
    let a2 = TestData.article(id: "2", publishedAt: TestData.now.addingTimeInterval(-60), categoryIDs: ["coding"], tags: ["swift"])
    let a3 = TestData.article(id: "3", publishedAt: TestData.now.addingTimeInterval(-120), categoryIDs: ["coding"])

    func makeDiscover(_ content: StubContentRepository) throws -> (DiscoverViewModel, LibraryStore) {
        let deps = try AppDependencies.test(content: content)
        let library = LibraryStore(repository: deps.library)
        return (DiscoverViewModel(dependencies: deps, library: library), library)
    }

    @Test func loadShowsFeedAndBriefing() async throws {
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: [a1, a2], nextCursor: nil))])
        let (vm, _) = try makeDiscover(content)
        await vm.load()
        #expect(vm.feed.value?.map(\.article.id) == ["1", "2"])
        #expect(vm.briefing?.introduction == "intro")
        #expect(vm.trendingTopics.contains("llm"))
    }

    @Test func emptyFeedProducesEmptyState() async throws {
        let (vm, _) = try makeDiscover(StubContentRepository())
        await vm.load()
        #expect(vm.feed.isEmpty)
    }

    @Test func offlineFailureIsActionableAndRetrySucceeds() async throws {
        let content = StubContentRepository(pages: [nil: .failure(.offline)])
        let (vm, _) = try makeDiscover(content)
        await vm.load()
        #expect(vm.feed.error == .offline)
        #expect(UserFacingError.offline.actionTitle == "Try Again")
        await content.setPage(nil, .success(ArticlePage(articles: [a1], nextCursor: nil)))
        await vm.load()
        #expect(vm.feed.value?.count == 1)
    }

    @Test func briefingFailureDoesNotBreakFeed() async throws {
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: [a1], nextCursor: nil))])
        await content.setBriefing(.failure(.http(status: 500)))
        let (vm, _) = try makeDiscover(content)
        await vm.load()
        #expect(vm.feed.value?.count == 1)
        #expect(vm.briefing == nil)
    }

    @Test func selectingCategoryReloadsFiltered() async throws {
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: [a1, a2, a3], nextCursor: nil))])
        let (vm, _) = try makeDiscover(content)
        await vm.select(category: "coding")
        #expect(vm.selectedCategoryID == "coding")
        #expect(vm.feed.value?.map(\.article.id) == ["2", "3"])
        #expect(await content.categoryFilterLog.last == "coding")
    }

    @Test func loadMoreAppendsNextPageDeduplicated() async throws {
        let content = StubContentRepository(pages: [
            nil: .success(ArticlePage(articles: [a1, a2], nextCursor: "p2")),
            "p2": .success(ArticlePage(articles: [a2, a3], nextCursor: nil)),
        ])
        let (vm, _) = try makeDiscover(content)
        await vm.load()
        await vm.loadMoreIfNeeded(after: a2.id)
        #expect(vm.feed.value?.map(\.article.id) == ["1", "2", "3"])
        #expect(vm.canLoadMore == false)
    }

    @Test func loadMoreOnlyTriggersNearEnd() async throws {
        let many = (0..<6).map { TestData.article(id: "m\($0)", publishedAt: TestData.now.addingTimeInterval(Double(-$0))) }
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: many, nextCursor: "p2"))])
        let (vm, _) = try makeDiscover(content)
        await vm.load()
        await vm.loadMoreIfNeeded(after: "m1")
        #expect(await content.categoryFilterLog.count == 1, "should not page when far from the end")
    }

    @Test func personalizationBoostsPreferredContentAndExplainsWhy() {
        var prefs = UserPreferences.default
        prefs.followedTechnologies = ["swift"]
        let ranked = FeedPersonalizer.rank([a1, a2], preferences: prefs)
        #expect(ranked.map(\.article.id) == ["2", "1"])
        #expect(ranked[0].reason == "Because you follow swift")
        #expect(ranked[1].reason == nil)
        prefs.personalizationEnabled = false
        #expect(FeedPersonalizer.rank([a1, a2], preferences: prefs).map(\.article.id) == ["1", "2"])
    }

    @Test func personalizationByCategory() {
        var prefs = UserPreferences.default
        prefs.selectedCategoryIDs = ["coding"]
        let ranked = FeedPersonalizer.rank([a1, a3], preferences: prefs)
        #expect(ranked.first?.article.id == "3")
        #expect(ranked.first?.reason == "Because you’re interested in Coding & Programming")
    }

    @Test func userFacingErrorMapping() {
        #expect(UserFacingError(APIError.offline) == .offline)
        #expect(UserFacingError(APIError.http(status: 503)) == .server)
        #expect(UserFacingError(APIError.decoding) == .unexpected)
        #expect(UserFacingError(RepositoryError.notFound) == .notFound)
    }

    // MARK: Article detail

    @Test func detailLoadsRecordsOpenAndRelated() async throws {
        let content = StubContentRepository(store: [a1, a2, a3])
        let deps = try AppDependencies.test(content: content)
        let library = LibraryStore(repository: deps.library)
        let vm = ArticleDetailViewModel(articleID: "1", dependencies: deps, library: library)
        await vm.load()
        #expect(vm.article.value?.id == "1")
        #expect(vm.related.map(\.id) == ["2", "3"])
        #expect(library.isRead("1"))
        #expect(try await deps.library.history().map(\.articleID) == ["1"])
    }

    @Test func detailMissingArticleShowsNotFound() async throws {
        let deps = try AppDependencies.test()
        let vm = ArticleDetailViewModel(articleID: "nope", dependencies: deps, library: LibraryStore(repository: deps.library))
        await vm.load()
        #expect(vm.article.error == .notFound)
    }

    @Test func detailFallsBackToOfflineCacheForSavedArticle() async throws {
        let deps = try AppDependencies.test()
        _ = try await deps.library.toggleBookmark(a1)
        let vm = ArticleDetailViewModel(articleID: "1", dependencies: deps, library: LibraryStore(repository: deps.library))
        await vm.load()
        #expect(vm.article.value?.id == "1")
        #expect(vm.isShowingOfflineCopy)
    }

    @Test func bookmarkAndNotesFromDetail() async throws {
        let deps = try AppDependencies.test(content: StubContentRepository(store: [a1]))
        let library = LibraryStore(repository: deps.library)
        let vm = ArticleDetailViewModel(articleID: "1", dependencies: deps, library: library)
        await vm.load()
        await vm.toggleBookmark()
        #expect(library.isBookmarked("1"))
        await vm.saveNote(text: "my note")
        #expect(vm.notes.map(\.text) == ["my note"])
        await vm.saveNote(text: "  ")
        #expect(vm.notes.count == 1)
        #expect(vm.noteError != nil)
        await vm.toggleBookmark()
        #expect(!library.isBookmarked("1"))
    }

    @Test func bodyPolicyRespectsContentAvailability() {
        let full = TestData.article(availability: .full)
        #expect(ArticleBodyPolicy.body(for: full) == .linkOnly, "full availability without content falls back")
        let excerpt = Article(id: "e", canonicalURL: URL(string: "https://example.com/e")!, title: "t", summary: nil,
                              excerpt: "an excerpt", content: "should not show", imageURL: nil, sourceID: "s", sourceName: "S",
                              author: nil, publishedAt: nil, fetchedAt: TestData.now, categoryIDs: [], tags: [],
                              readingTimeMinutes: nil, contentAvailability: .excerptOnly, difficulty: nil)
        #expect(ArticleBodyPolicy.body(for: excerpt) == .excerpt("an excerpt"))
    }
}
