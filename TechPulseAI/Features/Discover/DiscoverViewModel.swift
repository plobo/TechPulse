import Foundation
import Observation

struct FeedItem: Identifiable, Hashable, Sendable {
    let article: Article
    /// Plain-language explanation of why this was boosted (nil when not personalized).
    let reason: String?
    var id: ArticleID { article.id }
}

/// Transparent, rule-based personalization: preferred items move ahead of
/// others, recency order is preserved within each group.
enum FeedPersonalizer {
    static func rank(_ articles: [Article], preferences: UserPreferences) -> [FeedItem] {
        guard preferences.personalizationEnabled else { return articles.map { FeedItem(article: $0, reason: nil) } }
        let followed = Set(preferences.followedTechnologies.map { $0.lowercased() })
        let categories = Set(preferences.selectedCategoryIDs)
        let items = articles.map { article -> FeedItem in
            if let tech = article.tags.first(where: { followed.contains($0.lowercased()) }) {
                return FeedItem(article: article, reason: "Because you follow \(tech)")
            }
            if let cat = article.categoryIDs.first(where: categories.contains),
               let title = ArticleCategory.builtIn.first(where: { $0.id == cat })?.title {
                return FeedItem(article: article, reason: "Because you’re interested in \(title)")
            }
            return FeedItem(article: article, reason: nil)
        }
        return items.filter { $0.reason != nil } + items.filter { $0.reason == nil }
    }
}

@MainActor
@Observable
final class DiscoverViewModel {
    private(set) var feed: LoadState<[FeedItem]> = .idle
    private(set) var briefing: DailyBriefing?
    private(set) var briefingArticles: [Article] = []
    private(set) var categories: [ArticleCategory] = ArticleCategory.builtIn
    private(set) var selectedCategoryID: CategoryID?
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: UserFacingError?
    /// A refresh failed while older content is still on screen.
    private(set) var refreshError: UserFacingError?

    private var accumulator = FeedAccumulator()
    /// Display order. Already-shown items never move when later pages arrive.
    private var displayed: [FeedItem] = []
    /// Incremented per feed reset; responses from older generations are dropped.
    private var generation = 0
    private let dependencies: AppDependencies
    private let library: LibraryStore
    private let pageSize = 20

    var isSampleData: Bool { dependencies.isSampleData }
    var canLoadMore: Bool { accumulator.hasMore && feed.value != nil }

    var trendingTopics: [String] {
        var counts: [String: Int] = [:]
        for tag in accumulator.articles.flatMap(\.tags) { counts[tag, default: 0] += 1 }
        let fromFeed = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        var seen = Set<String>()
        return ((briefing?.keyThemes ?? []) + fromFeed).filter { seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    init(dependencies: AppDependencies, library: LibraryStore) {
        self.dependencies = dependencies
        self.library = library
    }

    func select(category: CategoryID?) async {
        guard category != selectedCategoryID || feed.value == nil else { return }
        selectedCategoryID = category
        accumulator.reset()
        displayed = []
        feed = .loading
        await load()
    }

    /// Initial load and pull-to-refresh.
    func load() async {
        generation += 1
        let current = generation
        if feed.value == nil { feed = .loading }
        refreshError = nil
        loadMoreError = nil
        async let briefingTask: Void = loadBriefing()
        async let categoriesTask = try? dependencies.catalog.categories()
        do {
            let page = try await dependencies.articles.articles(ArticleQuery(categoryID: selectedCategoryID, limit: pageSize))
            if current == generation {
                var fresh = FeedAccumulator()
                fresh.append(page)
                accumulator = fresh
                displayed = FeedPersonalizer.rank(fresh.articles, preferences: library.preferences)
                publishFeed()
            }
        } catch is CancellationError {
            // View went away; keep previous state.
        } catch {
            if current == generation {
                if feed.value == nil { feed = .failed(UserFacingError(error)) } else { refreshError = UserFacingError(error) }
            }
        }
        await briefingTask
        if let cats = await categoriesTask, !cats.isEmpty { categories = cats }
    }

    /// Re-rank locally after a preference change (no refetch).
    func applyPreferences() {
        guard feed.value != nil else { return }
        displayed = FeedPersonalizer.rank(accumulator.articles, preferences: library.preferences)
        publishFeed()
    }

    func loadMoreIfNeeded(after articleID: ArticleID) async {
        guard canLoadMore, !isLoadingMore,
              let index = displayed.firstIndex(where: { $0.id == articleID }),
              index >= displayed.count - 3 else { return }
        let current = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await dependencies.articles.articles(
                ArticleQuery(categoryID: selectedCategoryID, cursor: accumulator.nextCursor, limit: pageSize))
            guard current == generation else { return }
            let shown = Set(displayed.map(\.id))
            accumulator.append(page)
            let newArticles = accumulator.articles.filter { !shown.contains($0.id) }
            displayed += FeedPersonalizer.rank(newArticles, preferences: library.preferences)
            publishFeed()
        } catch is CancellationError {
        } catch {
            if current == generation { loadMoreError = UserFacingError(error) }
        }
    }

    func retryLoadMore() async {
        loadMoreError = nil
        if let last = displayed.last { await loadMoreIfNeeded(after: last.id) }
    }

    private func publishFeed() {
        feed = displayed.isEmpty ? .empty : .loaded(displayed)
    }

    private func loadBriefing() async {
        do {
            let result = try await dependencies.briefing.dailyBriefing()
            briefing = result
            var articles: [Article] = []
            for id in result.articleIDs.prefix(5) {
                if let article = try? await dependencies.articles.article(id: id) { articles.append(article) }
            }
            briefingArticles = articles
        } catch {
            briefing = nil
            briefingArticles = []
        }
    }
}
