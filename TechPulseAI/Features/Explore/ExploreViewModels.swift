import Foundation
import Observation

enum DateRangeFilter: String, CaseIterable, Sendable, Hashable {
    case any, day, week, month

    var title: String {
        switch self {
        case .any: "Any time"
        case .day: "Past 24 hours"
        case .week: "Past week"
        case .month: "Past month"
        }
    }

    func lowerBound(now: Date) -> Date? {
        switch self {
        case .any: nil
        case .day: now.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-30 * 86_400)
        }
    }
}

@MainActor
@Observable
final class ExploreViewModel {
    private(set) var state: LoadState<Void> = .idle
    private(set) var categories: [ArticleCategory] = []
    private(set) var sources: [Source] = []
    private(set) var trendingTags: [String] = []
    private let dependencies: AppDependencies

    var isSampleData: Bool { dependencies.isSampleData }

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func load() async {
        if categories.isEmpty { state = .loading }
        do {
            async let cats = dependencies.catalog.categories()
            async let srcs = dependencies.catalog.sources()
            async let recent = dependencies.articles.articles(ArticleQuery(limit: 50))
            categories = try await cats
            sources = try await srcs.filter(\.isEnabled)
            var counts: [String: Int] = [:]
            for tag in (try? await recent)?.articles.flatMap(\.tags) ?? [] { counts[tag, default: 0] += 1 }
            trendingTags = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(12).map(\.key)
            state = .loaded(())
        } catch is CancellationError {
        } catch {
            state = .failed(UserFacingError(error))
        }
    }
}

/// Paged list of articles for a category or source topic page, with local filters.
@MainActor
@Observable
final class ArticleListViewModel {
    enum Kind: Hashable, Sendable {
        case category(CategoryID)
        case source(SourceID)
    }

    let kind: Kind
    private(set) var state: LoadState<Void> = .idle
    private(set) var title: String
    private(set) var isLoadingMore = false
    var difficulty: Difficulty?
    var dateRange: DateRangeFilter = .any

    private var accumulator = FeedAccumulator()
    private let dependencies: AppDependencies

    init(kind: Kind, dependencies: AppDependencies) {
        self.kind = kind
        self.dependencies = dependencies
        switch kind {
        case let .category(id): title = ArticleFormatting.categoryTitle(id) ?? id
        case .source: title = "Source"
        }
    }

    private var query: ArticleQuery {
        switch kind {
        case let .category(id): ArticleQuery(categoryID: id, limit: 30)
        case let .source(id): ArticleQuery(sourceIDs: [id], limit: 30)
        }
    }

    var visibleItems: [FeedItem] {
        let from = dateRange.lowerBound(now: dependencies.dateProvider.now)
        return accumulator.articles
            .filter { difficulty == nil || $0.difficulty == difficulty }
            .filter { article in
                guard let from else { return true }
                return (article.publishedAt ?? .distantPast) >= from
            }
            .map { FeedItem(article: $0, reason: nil) }
    }

    var hasActiveFilters: Bool { difficulty != nil || dateRange != .any }

    func load() async {
        if accumulator.articles.isEmpty { state = .loading }
        do {
            if case let .source(id) = kind, let source = try? await dependencies.catalog.sources().first(where: { $0.id == id }) {
                title = source.name
            }
            let page = try await dependencies.articles.articles(query)
            var fresh = FeedAccumulator()
            fresh.append(page)
            accumulator = fresh
            state = accumulator.articles.isEmpty ? .empty : .loaded(())
        } catch is CancellationError {
        } catch {
            state = .failed(UserFacingError(error))
        }
    }

    func loadMoreIfNeeded(after id: ArticleID) async {
        guard accumulator.hasMore, !isLoadingMore, accumulator.articles.last?.id == id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        var next = query
        next.cursor = accumulator.nextCursor
        if let page = try? await dependencies.articles.articles(next) { accumulator.append(page) }
    }
}

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var categoryID: CategoryID?
    var sourceID: SourceID?
    var dateRange: DateRangeFilter = .any
    var difficulty: Difficulty?
    var sort: ArticleSort = .relevance
    private(set) var results: LoadState<[Article]> = .idle
    private(set) var sources: [Source] = []
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies, initialQuery: String = "") {
        self.dependencies = dependencies
        self.query = initialQuery
    }

    /// Identity of the current request; the view re-runs search when it changes.
    var requestKey: String {
        [query, categoryID ?? "", sourceID ?? "", dateRange.rawValue, difficulty?.rawValue ?? "", sort.rawValue].joined(separator: "|")
    }

    var hasActiveFilters: Bool { categoryID != nil || sourceID != nil || dateRange != .any || difficulty != nil }

    func loadSources() async {
        if sources.isEmpty { sources = (try? await dependencies.catalog.sources()) ?? [] }
    }

    func clearFilters() {
        categoryID = nil
        sourceID = nil
        dateRange = .any
        difficulty = nil
    }

    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = .idle
            return
        }
        results = .loading
        let request = SearchQuery(text: text, categoryID: categoryID, sourceID: sourceID,
                                  from: dateRange.lowerBound(now: dependencies.dateProvider.now),
                                  to: nil, difficulty: difficulty, sort: sort)
        do {
            let found = try await dependencies.articles.search(request)
            try Task.checkCancellation()
            results = found.isEmpty ? .empty : .loaded(found)
        } catch is CancellationError {
        } catch {
            results = .failed(UserFacingError(error))
        }
    }
}
