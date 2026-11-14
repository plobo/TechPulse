import Foundation
import Testing
@testable import TechPulseAI

@Suite("DTO decoding and mapping")
struct DTOAndMapperTests {
    let json = Data("""
    {
      "items": [
        {
          "id": "a1",
          "canonical_url": "https://example.com/post-1",
          "title": "Hello",
          "summary": "Short summary",
          "excerpt": "Excerpt",
          "image_url": null,
          "source_id": "s1",
          "source_name": "Example Source",
          "author": "Ada",
          "published_at": "2026-11-13T09:30:00Z",
          "category_ids": ["ai-ml"],
          "tags": ["llm"],
          "reading_time_minutes": 4,
          "content_availability": "excerpt_only"
        },
        {
          "id": "a2",
          "canonical_url": "https://example.com/post-2",
          "title": "Minimal",
          "source_id": "s1",
          "source_name": "Example Source",
          "content_availability": "something_new"
        }
      ],
      "next_cursor": "abc"
    }
    """.utf8)

    @Test func decodesPageWithOptionalFieldsAndDates() throws {
        let page = try JSONDecoder.techPulse.decode(ArticlePageDTO.self, from: json)
        #expect(page.items.count == 2)
        #expect(page.nextCursor == "abc")
        #expect(page.items[0].publishedAt == ISO8601DateFormatter().date(from: "2026-11-13T09:30:00Z"))
        #expect(page.items[1].tags == nil)
    }

    @Test func mapsDTOToDomainArticle() throws {
        let dto = try JSONDecoder.techPulse.decode(ArticlePageDTO.self, from: json).items[0]
        let article = try ArticleMapper.map(dto, fetchedAt: TestData.now)
        #expect(article.id == "a1")
        #expect(article.canonicalURL.absoluteString == "https://example.com/post-1")
        #expect(article.author == "Ada")
        #expect(article.readingTimeMinutes == 4)
        #expect(article.contentAvailability == .excerptOnly)
        #expect(article.fetchedAt == TestData.now)
    }

    @Test func unknownAvailabilityFallsBackToLinkOnlyAndMissingArraysAreEmpty() throws {
        let dto = try JSONDecoder.techPulse.decode(ArticlePageDTO.self, from: json).items[1]
        let article = try ArticleMapper.map(dto, fetchedAt: TestData.now)
        #expect(article.contentAvailability == .linkOnly)
        #expect(article.tags.isEmpty)
        #expect(article.categoryIDs.isEmpty)
    }

    @Test func rejectsNonHTTPCanonicalURL() {
        let dto = ArticleDTO(id: "x", canonicalURL: "javascript:alert(1)", title: "t", summary: nil, excerpt: nil,
                             content: nil, imageURL: nil, sourceID: "s", sourceName: "S", author: nil,
                             publishedAt: nil, categoryIDs: nil, tags: nil, readingTimeMinutes: nil,
                             contentAvailability: nil, difficulty: nil)
        #expect(throws: MappingError.self) { try ArticleMapper.map(dto, fetchedAt: TestData.now) }
    }

    @Test func mapPageDropsInvalidItemsInsteadOfFailingWholePage() {
        let good = ArticleDTO(id: "g", canonicalURL: "https://example.com/g", title: "t", summary: nil, excerpt: nil,
                              content: nil, imageURL: nil, sourceID: "s", sourceName: "S", author: nil,
                              publishedAt: nil, categoryIDs: nil, tags: nil, readingTimeMinutes: nil,
                              contentAvailability: nil, difficulty: nil)
        var bad = good
        bad.canonicalURL = "not a url"
        let page = ArticleMapper.map(ArticlePageDTO(items: [bad, good], nextCursor: nil), fetchedAt: TestData.now)
        #expect(page.articles.map(\.id) == ["g"])
    }

    @Test func estimatesReadingTimeWhenMissing() throws {
        let words = Array(repeating: "word", count: 450).joined(separator: " ")
        let dto = ArticleDTO(id: "r", canonicalURL: "https://example.com/r", title: "t", summary: nil, excerpt: nil,
                             content: words, imageURL: nil, sourceID: "s", sourceName: "S", author: nil,
                             publishedAt: nil, categoryIDs: nil, tags: nil, readingTimeMinutes: nil,
                             contentAvailability: "full", difficulty: nil)
        #expect(try ArticleMapper.map(dto, fetchedAt: TestData.now).readingTimeMinutes == 3)
    }

    @Test func readingTimeEstimator() {
        #expect(ReadingTimeEstimator.minutes(for: "") == nil)
        #expect(ReadingTimeEstimator.minutes(for: "one two three") == 1)
        #expect(ReadingTimeEstimator.minutes(for: Array(repeating: "w", count: 221).joined(separator: " ")) == 2)
    }
}
