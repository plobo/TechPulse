import Foundation
import Testing
@testable import TechPulseAI

@Suite("Deduplication, sorting and pagination")
struct DeduplicationAndSortTests {
    @Test func normalizesCanonicalURLs() {
        let a = URL(string: "https://Example.com/post/?utm_source=x&id=2#frag")!
        let b = URL(string: "https://example.com/post?id=2")!
        #expect(ArticleDeduplicator.key(for: a) == ArticleDeduplicator.key(for: b))
    }

    @Test func dedupesByIDAndCanonicalURLKeepingFirst() {
        let first = TestData.article(id: "1", url: "https://example.com/a", title: "first")
        let sameURL = TestData.article(id: "2", url: "https://example.com/a/", title: "dup url")
        let sameID = TestData.article(id: "1", url: "https://example.com/z", title: "dup id")
        let other = TestData.article(id: "3", url: "https://example.com/b")
        let result = ArticleDeduplicator.dedupe([first, sameURL, sameID, other])
        #expect(result.map(\.id) == ["1", "3"])
        #expect(result[0].title == "first")
    }

    @Test func feedAccumulatorAppendsPagesWithoutDuplicates() {
        var feed = FeedAccumulator()
        feed.append(ArticlePage(articles: [TestData.article(id: "1"), TestData.article(id: "2")], nextCursor: "c1"))
        feed.append(ArticlePage(articles: [TestData.article(id: "2"), TestData.article(id: "3")], nextCursor: nil))
        #expect(feed.articles.map(\.id) == ["1", "2", "3"])
        #expect(feed.hasMore == false)
        feed.reset()
        #expect(feed.articles.isEmpty && feed.hasMore)
    }

    @Test func newestSortPutsUndatedLast() {
        let old = TestData.article(id: "old", publishedAt: TestData.now.addingTimeInterval(-3600))
        let new = TestData.article(id: "new", publishedAt: TestData.now)
        let undated = TestData.article(id: "none", publishedAt: nil)
        #expect(ArticleSort.newest.sorted([undated, old, new], query: "").map(\.id) == ["new", "old", "none"])
    }

    @Test func relevanceSortRanksTitleMatchesAboveTagAndSummaryMatches() {
        let summaryHit = TestData.article(id: "s", title: "Other", summary: "about swift concurrency")
        let titleHit = TestData.article(id: "t", title: "Swift actors explained", publishedAt: TestData.now.addingTimeInterval(-9999))
        let tagHit = TestData.article(id: "g", title: "Misc", tags: ["swift"])
        #expect(ArticleSort.relevance.sorted([summaryHit, tagHit, titleHit], query: "swift").map(\.id) == ["t", "g", "s"])
    }

    @Test func searchMatcherMatchesTitleSourceTagsAndSummaryCaseInsensitively() {
        let a = TestData.article(title: "Rust", summary: nil, sourceName: "Kernel Blog", tags: ["systems"])
        #expect(ArticleSearchMatcher.matches(a, query: "kernel"))
        #expect(ArticleSearchMatcher.matches(a, query: "SYSTEMS"))
        #expect(ArticleSearchMatcher.matches(a, query: "rust kernel"))
        #expect(!ArticleSearchMatcher.matches(a, query: "python"))
    }
}
