import Foundation
@testable import TechPulseAI

enum TestData {
    static let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!

    static func article(
        id: String = UUID().uuidString,
        url: String? = nil,
        title: String = "Title",
        summary: String? = nil,
        sourceID: String = "src",
        sourceName: String = "Source",
        publishedAt: Date? = TestData.now,
        categoryIDs: [String] = ["ai-ml"],
        tags: [String] = [],
        availability: ContentAvailability = .excerptOnly
    ) -> Article {
        Article(
            id: id,
            canonicalURL: URL(string: url ?? "https://example.com/\(id)")!,
            title: title,
            summary: summary,
            excerpt: nil,
            content: nil,
            imageURL: nil,
            sourceID: sourceID,
            sourceName: sourceName,
            author: nil,
            publishedAt: publishedAt,
            fetchedAt: TestData.now,
            categoryIDs: categoryIDs,
            tags: tags,
            readingTimeMinutes: 3,
            contentAvailability: availability,
            difficulty: nil
        )
    }
}

/// Scripted HTTP client: returns queued results in order and records requests.
actor MockHTTPClient: HTTPClient {
    enum Reply {
        case response(status: Int, body: Data, headers: [String: String] = [:])
        case failure(any Error)
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() {
        case let .response(status, body, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (body, response)
        case let .failure(error):
            throw error
        }
    }
}

/// Records backoff delays instead of sleeping.
actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func record(_ d: Duration) { delays.append(d) }
}

struct FixedDateProvider: DateProvider {
    let now: Date
}
