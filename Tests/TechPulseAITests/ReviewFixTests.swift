import Foundation
import Testing
@testable import TechPulseAI

@MainActor
@Suite("Final review fixes")
struct ReviewFixTests {
    func items(_ prefix: String, _ n: Int, swiftFrom: Int = .max, start: Int = 0) -> [Article] {
        (0..<n).map { i in
            TestData.article(id: "\(prefix)\(i)", publishedAt: TestData.now.addingTimeInterval(Double(-(start + i) * 60)),
                             categoryIDs: ["coding"], tags: i >= swiftFrom ? ["swift"] : [])
        }
    }

    func makeDiscover(_ content: StubContentRepository, follow: [String] = []) async throws -> DiscoverViewModel {
        let deps = try AppDependencies.test(content: content)
        let library = LibraryStore(repository: deps.library)
        if !follow.isEmpty { await library.updatePreferences { $0.followedTechnologies = follow } }
        return DiscoverViewModel(dependencies: deps, library: library)
    }

    // I-1
    @Test func loadMoreTriggersOnLastDisplayedItemUnderPersonalization() async throws {
        let page1 = items("f", 6, swiftFrom: 3)
        let content = StubContentRepository(pages: [
            nil: .success(ArticlePage(articles: page1, nextCursor: "p2")),
            "p2": .success(ArticlePage(articles: items("g", 2, start: 10), nextCursor: nil)),
        ])
        let vm = try await makeDiscover(content, follow: ["swift"])
        await vm.load()
        let shown = try #require(vm.feed.value).map(\.id)
        #expect(shown == ["f3", "f4", "f5", "f0", "f1", "f2"])
        await vm.loadMoreIfNeeded(after: "f2")
        #expect(vm.feed.value?.map(\.id).suffix(2) == ["g0", "g1"])
    }

    @Test func itemsAlreadyShownDoNotMoveWhenNextPageHasBoostedItems() async throws {
        let content = StubContentRepository(pages: [
            nil: .success(ArticlePage(articles: items("f", 4), nextCursor: "p2")),
            "p2": .success(ArticlePage(articles: items("g", 2, swiftFrom: 0, start: 10), nextCursor: nil)),
        ])
        let vm = try await makeDiscover(content, follow: ["swift"])
        await vm.load()
        await vm.loadMoreIfNeeded(after: "f3")
        #expect(vm.feed.value?.map(\.id) == ["f0", "f1", "f2", "f3", "g0", "g1"])
    }

    // I-2
    @Test func staleCategoryResponseDoesNotOverwriteNewerSelection() async throws {
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: [
            TestData.article(id: "ai", categoryIDs: ["ai-ml"]), TestData.article(id: "code", categoryIDs: ["coding"]),
        ], nextCursor: nil))])
        await content.setDelay("ai-ml", .milliseconds(300))
        let vm = try await makeDiscover(content)
        let slow = Task { await vm.select(category: "ai-ml") }
        try await Task.sleep(for: .milliseconds(50))
        await vm.select(category: "coding")
        await slow.value
        #expect(vm.selectedCategoryID == "coding")
        #expect(vm.feed.value?.map(\.id) == ["code"])
    }

    @Test func failedCategorySwitchShowsErrorInsteadOfOldArticles() async throws {
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: items("f", 2), nextCursor: nil))])
        let vm = try await makeDiscover(content)
        await vm.load()
        await content.setPage(nil, .failure(.offline))
        await vm.select(category: "coding")
        #expect(vm.feed.error == .offline)
    }

    @Test func failedRefreshKeepsFeedAndSurfacesError() async throws {
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: items("f", 2), nextCursor: nil))])
        let vm = try await makeDiscover(content)
        await vm.load()
        await content.setPage(nil, .failure(.offline))
        await vm.load()
        #expect(vm.feed.value?.count == 2)
        #expect(vm.refreshError == .offline)
    }

    @Test func preferenceChangeReranksWithoutRefetching() async throws {
        let content = StubContentRepository(pages: [nil: .success(ArticlePage(articles: items("f", 3, swiftFrom: 2), nextCursor: nil))])
        let deps = try AppDependencies.test(content: content)
        let library = LibraryStore(repository: deps.library)
        let vm = DiscoverViewModel(dependencies: deps, library: library)
        await vm.load()
        let fetches = await content.categoryFilterLog.count
        await library.updatePreferences { $0.followedTechnologies = ["swift"] }
        vm.applyPreferences()
        #expect(vm.feed.value?.first?.id == "f2")
        #expect(await content.categoryFilterLog.count == fetches)
    }

    // I-3
    @Test func topicPageKeepsFetchingWhenFiltersHideFetchedItems() async throws {
        let old = (0..<3).map { TestData.article(id: "old\($0)", publishedAt: TestData.now.addingTimeInterval(-20 * 86_400), categoryIDs: ["coding"]) }
        let recent = TestData.article(id: "recent", publishedAt: TestData.now, categoryIDs: ["coding"])
        let content = StubContentRepository(pages: [
            nil: .success(ArticlePage(articles: old, nextCursor: "p2")),
            "p2": .success(ArticlePage(articles: [recent], nextCursor: nil)),
        ])
        let vm = ArticleListViewModel(kind: .category("coding"), dependencies: try .test(content: content))
        vm.dateRange = .week
        await vm.load()
        #expect(vm.visibleItems.map(\.article.id) == ["recent"])
    }

    @Test func topicPageLoadMoreUsesLastVisibleItemAndSurfacesErrors() async throws {
        let content = StubContentRepository(pages: [
            nil: .success(ArticlePage(articles: items("f", 12), nextCursor: "p2")),
            "p2": .failure(.http(status: 500)),
        ])
        let vm = ArticleListViewModel(kind: .category("coding"), dependencies: try .test(content: content))
        await vm.load()
        await vm.loadMoreIfNeeded(after: "f11")
        #expect(vm.loadMoreError == .server)
    }

    // I-4
    @Test func remoteSourceQueryIsSentToServer() async throws {
        let http = MockHTTPClient([.response(status: 200, body: Data(#"{"items":[],"next_cursor":null}"#.utf8))])
        let repo = RemoteContentRepository(client: APIClient(baseURL: URL(string: "https://api.example.com")!, http: http),
                                           dateProvider: FixedDateProvider(now: TestData.now))
        _ = try await repo.articles(ArticleQuery(sourceIDs: ["s1"], limit: 10))
        let url = try #require(await http.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "source", value: "s1")))
    }

    // I-5
    @Test func deleteAllFailureIsReportedNotClaimedAsSuccess() async throws {
        let store = LibraryStore(repository: FailingLibraryRepository())
        await store.load()
        let vm = SettingsViewModel(library: store, notifications: StubNotificationAuthorizer(grant: true))
        await vm.deleteAllData()
        #expect(vm.storageMessage?.hasPrefix("Couldn’t") == true)
    }

    @Test func deleteAllRemovesExportFileAndClearsNetworkCache() async throws {
        let deps = try AppDependencies.test()
        let store = LibraryStore(repository: deps.library)
        let flag = CallFlag()
        let vm = SettingsViewModel(library: store, notifications: StubNotificationAuthorizer(grant: true),
                                   clearNetworkCache: { flag.hit() })
        let url = try #require(await vm.exportData())
        #expect(FileManager.default.fileExists(atPath: url.path))
        await vm.deleteAllData()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(flag.count == 1)
        #expect(vm.storageMessage == "All on-device data deleted.")
    }

    @Test func failedLibraryMutationsDoNotPretendToSucceed() async throws {
        let store = LibraryStore(repository: FailingLibraryRepository())
        await store.load()
        #expect(store.isBookmarked("ai") && store.isRead("ai"))
        await store.removeBookmark("ai")
        #expect(store.isBookmarked("ai"))
        await store.clearHistory()
        #expect(store.isRead("ai"))
        #expect(store.lastErrorMessage != nil)
    }

    // M-8 (promoted)
    @Test func voiceOverLabelIncludesPersonalizationReason() {
        let label = ArticleFormatting.accessibilityLabel(for: TestData.article(), now: TestData.now, isBookmarked: false,
                                                         isRead: false, reason: "Because you follow swift")
        #expect(label.contains("Because you follow swift"))
    }
}
