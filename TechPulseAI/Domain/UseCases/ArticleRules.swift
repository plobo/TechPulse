import Foundation

enum ReadingTimeEstimator {
    static let wordsPerMinute = 220

    static func minutes(for text: String) -> Int? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard words > 0 else { return nil }
        return Int((Double(words) / Double(wordsPerMinute)).rounded(.up))
    }
}

enum ArticleDeduplicator {
    private static let trackingPrefixes = ["utm_", "fbclid", "gclid", "mc_"]

    /// Canonical key: lowercased scheme/host, no fragment, no trailing slash, tracking params removed, params sorted.
    static func key(for url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        comps.scheme = comps.scheme?.lowercased()
        comps.host = comps.host?.lowercased()
        comps.fragment = nil
        var path = comps.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }
        comps.path = path
        let items = (comps.queryItems ?? [])
            .filter { item in !trackingPrefixes.contains { item.name.lowercased().hasPrefix($0) } }
            .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        comps.queryItems = items.isEmpty ? nil : items
        return comps.string ?? url.absoluteString
    }

    static func dedupe(_ articles: [Article]) -> [Article] {
        var seenIDs = Set<ArticleID>()
        var seenURLs = Set<String>()
        return articles.filter { article in
            let urlKey = key(for: article.canonicalURL)
            guard !seenIDs.contains(article.id), !seenURLs.contains(urlKey) else { return false }
            seenIDs.insert(article.id)
            seenURLs.insert(urlKey)
            return true
        }
    }
}

/// Accumulates paginated feed results, deduplicating across pages.
struct FeedAccumulator: Sendable {
    private(set) var articles: [Article] = []
    private(set) var nextCursor: String?
    private(set) var hasMore = true

    mutating func append(_ page: ArticlePage) {
        articles = ArticleDeduplicator.dedupe(articles + page.articles)
        nextCursor = page.nextCursor
        hasMore = page.nextCursor != nil
    }

    mutating func reset() {
        articles = []
        nextCursor = nil
        hasMore = true
    }
}

enum ArticleSearchMatcher {
    static func terms(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// All terms must appear in title, source, tags or summary.
    static func matches(_ article: Article, query: String) -> Bool {
        let haystack = [article.title, article.sourceName, article.summary ?? "", article.tags.joined(separator: " ")]
            .joined(separator: " ").lowercased()
        let terms = terms(query)
        return !terms.isEmpty && terms.allSatisfy(haystack.contains)
    }

    static func score(_ article: Article, query: String) -> Int {
        terms(query).reduce(0) { total, term in
            var s = 0
            if article.title.lowercased().contains(term) { s += 3 }
            if article.tags.contains(where: { $0.lowercased().contains(term) }) { s += 2 }
            if article.sourceName.lowercased().contains(term) { s += 1 }
            if article.summary?.lowercased().contains(term) == true { s += 1 }
            return total + s
        }
    }
}

extension ArticleSort {
    func sorted(_ articles: [Article], query: String) -> [Article] {
        let byDate: (Article, Article) -> Bool = { lhs, rhs in
            switch (lhs.publishedAt, rhs.publishedAt) {
            case let (l?, r?): l > r
            case (_?, nil): true
            default: false
            }
        }
        switch self {
        case .newest:
            return articles.sorted(by: byDate)
        case .relevance:
            return articles
                .map { ($0, ArticleSearchMatcher.score($0, query: query)) }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : byDate($0.0, $1.0) }
                .map(\.0)
        }
    }
}
