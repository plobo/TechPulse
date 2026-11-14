import Foundation
import Testing
@testable import TechPulseAI

@Suite("Sample repositories and briefing")
struct SampleRepositoryTests {
    func makeRepo() throws -> SampleContentRepository {
        try SampleContentRepository(fixtures: SampleFixtures.load(from: .main), dateProvider: FixedDateProvider(now: TestData.now))
    }

    @Test func fixturesLoadAndCoverAllEightCategories() async throws {
        let repo = try makeRepo()
        let categories = try await repo.categories()
        #expect(categories.map(\.id) == ArticleCategory.allIDs)
        let all = try await repo.articles(ArticleQuery(limit: 100)).articles
        #expect(all.count >= 16)
        for id in ArticleCategory.allIDs {
            #expect(all.contains { $0.categoryIDs.contains(id) }, "no sample article for \(id)")
        }
        #expect(all.allSatisfy { $0.canonicalURL.host == "example.com" }, "sample data must not point at real publishers")
    }

    @Test func paginatesWithCursorNewestFirst() async throws {
        let repo = try makeRepo()
        let first = try await repo.articles(ArticleQuery(limit: 5))
        #expect(first.articles.count == 5)
        #expect(first.nextCursor != nil)
        let second = try await repo.articles(ArticleQuery(cursor: first.nextCursor, limit: 5))
        #expect(Set(first.articles.map(\.id)).isDisjoint(with: second.articles.map(\.id)))
        let dates = (first.articles + second.articles).compactMap(\.publishedAt)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func filtersByCategoryAndSource() async throws {
        let repo = try makeRepo()
        let ai = try await repo.articles(ArticleQuery(categoryID: "ai-ml", limit: 100)).articles
        #expect(!ai.isEmpty && ai.allSatisfy { $0.categoryIDs.contains("ai-ml") })
        let sourceID = ai[0].sourceID
        let bySource = try await repo.articles(ArticleQuery(sourceIDs: [sourceID], limit: 100)).articles
        #expect(bySource.allSatisfy { $0.sourceID == sourceID })
    }

    @Test func searchAppliesTextCategoryAndDateFilters() async throws {
        let repo = try makeRepo()
        #expect(try await repo.search(SearchQuery(text: "   ")).isEmpty)
        let results = try await repo.search(SearchQuery(text: "sample", sort: .newest))
        #expect(!results.isEmpty)
        let from = TestData.now.addingTimeInterval(-2 * 86_400)
        let recent = try await repo.search(SearchQuery(text: "sample", from: from))
        #expect(recent.allSatisfy { ($0.publishedAt ?? .distantPast) >= from })
        #expect(recent.count < results.count)
    }

    @Test func lookupAndRelatedArticles() async throws {
        let repo = try makeRepo()
        let first = try await repo.articles(ArticleQuery(limit: 1)).articles[0]
        #expect(try await repo.article(id: first.id) == first)
        await #expect(throws: RepositoryError.notFound) { try await repo.article(id: "missing") }
        let related = try await repo.relatedArticles(to: first, limit: 3)
        #expect(related.count <= 3 && !related.contains(first))
        #expect(related.allSatisfy { !Set($0.categoryIDs).isDisjoint(with: first.categoryIDs) || !Set($0.tags).isDisjoint(with: first.tags) })
    }

    @Test func briefingBuilderPicksRecentDiverseArticlesAndThemes() {
        let articles = [
            TestData.article(id: "1", publishedAt: TestData.now.addingTimeInterval(-3600), categoryIDs: ["ai-ml"], tags: ["llm", "agents"]),
            TestData.article(id: "2", publishedAt: TestData.now.addingTimeInterval(-7200), categoryIDs: ["ai-ml"], tags: ["llm"]),
            TestData.article(id: "3", publishedAt: TestData.now.addingTimeInterval(-9000), categoryIDs: ["coding"], tags: ["swift"]),
            TestData.article(id: "old", publishedAt: TestData.now.addingTimeInterval(-10 * 86_400), categoryIDs: ["career"]),
        ]
        let briefing = DailyBriefingBuilder.build(from: articles, now: TestData.now, maxArticles: 2)
        #expect(briefing.articleIDs == ["1", "3"], "one per category first, newest first")
        #expect(briefing.keyThemes.first == "llm")
        #expect(!briefing.articleIDs.contains("old"))
        #expect(briefing.isAIGenerated == false)
        #expect(!briefing.introduction.isEmpty)
    }

    @Test func briefingIsEmptyWhenNothingRecent() {
        let briefing = DailyBriefingBuilder.build(from: [], now: TestData.now)
        #expect(briefing.articleIDs.isEmpty)
    }
}
