import Foundation
import Testing
@testable import TechPulseAI

@Suite("APIClient")
struct APIClientTests {
    let base = URL(string: "https://api.example.com")!
    let categoriesJSON = Data(#"[{"id":"ai-ml","title":"AI","description":"d","icon":"brain"}]"#.utf8)

    func makeClient(_ http: MockHTTPClient, recorder: SleepRecorder = SleepRecorder(), maxAttempts: Int = 3) -> APIClient {
        APIClient(baseURL: base, http: http,
                  retryPolicy: RetryPolicy(maxAttempts: maxAttempts, baseDelay: .milliseconds(500), maxDelay: .seconds(8)),
                  sleep: { await recorder.record($0) })
    }

    @Test func buildsRequestURLWithQueryItems() async throws {
        let http = MockHTTPClient([.response(status: 200, body: Data(#"{"items":[],"next_cursor":null}"#.utf8))])
        _ = try await makeClient(http).send(Endpoint.articles(category: "ai-ml", cursor: "c2", limit: 20), as: ArticlePageDTO.self)
        let url = await http.requests.first?.url
        let comps = URLComponents(url: url!, resolvingAgainstBaseURL: false)!
        #expect(comps.path == "/v1/articles")
        #expect(Set(comps.queryItems ?? []) == [URLQueryItem(name: "category", value: "ai-ml"),
                                                URLQueryItem(name: "cursor", value: "c2"),
                                                URLQueryItem(name: "limit", value: "20")])
        #expect(await http.requests.first?.timeoutInterval == 15)
    }

    @Test func decodesSuccessfulResponse() async throws {
        let http = MockHTTPClient([.response(status: 200, body: categoriesJSON)])
        let result = try await makeClient(http).send(.categories, as: [CategoryDTO].self)
        #expect(result.first?.id == "ai-ml")
    }

    @Test func clientErrorIsNotRetried() async {
        let http = MockHTTPClient([.response(status: 404, body: Data())])
        await #expect(throws: APIError.http(status: 404)) {
            try await makeClient(http).send(.categories, as: [CategoryDTO].self)
        }
        #expect(await http.requests.count == 1)
    }

    @Test func transientErrorsRetryWithExponentialBackoffThenSucceed() async throws {
        let recorder = SleepRecorder()
        let http = MockHTTPClient([.response(status: 503, body: Data()),
                                   .failure(URLError(.timedOut)),
                                   .response(status: 200, body: categoriesJSON)])
        let result = try await makeClient(http, recorder: recorder).send(.categories, as: [CategoryDTO].self)
        #expect(result.count == 1)
        #expect(await recorder.delays == [.milliseconds(500), .milliseconds(1000)])
    }

    @Test func retriesAreBounded() async {
        let http = MockHTTPClient(Array(repeating: .response(status: 500, body: Data()), count: 10))
        await #expect(throws: APIError.http(status: 500)) {
            try await makeClient(http, maxAttempts: 3).send(.categories, as: [CategoryDTO].self)
        }
        #expect(await http.requests.count == 3)
    }

    @Test func backoffDelayIsCapped() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: .seconds(1), maxDelay: .seconds(5))
        #expect(policy.delay(afterAttempt: 1) == .seconds(1))
        #expect(policy.delay(afterAttempt: 3) == .seconds(4))
        #expect(policy.delay(afterAttempt: 6) == .seconds(5))
    }

    @Test func offlineMapsToOfflineError() async {
        let http = MockHTTPClient([.failure(URLError(.notConnectedToInternet))])
        await #expect(throws: APIError.offline) {
            try await makeClient(http).send(.categories, as: [CategoryDTO].self)
        }
        #expect(await http.requests.count == 1)
    }

    @Test func decodingFailureIsReported() async {
        let http = MockHTTPClient([.response(status: 200, body: Data("{oops".utf8))])
        await #expect(throws: APIError.decoding) {
            try await makeClient(http).send(.categories, as: [CategoryDTO].self)
        }
    }

    @Test func sendsIfNoneMatchAndReusesCachedBodyOn304() async throws {
        let http = MockHTTPClient([.response(status: 200, body: categoriesJSON, headers: ["ETag": "\"v1\""]),
                                   .response(status: 304, body: Data())])
        let client = makeClient(http)
        _ = try await client.send(.categories, as: [CategoryDTO].self)
        let second = try await client.send(.categories, as: [CategoryDTO].self)
        #expect(second.first?.id == "ai-ml")
        #expect(await http.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    }

    @Test func cancellationIsPropagatedWithoutRetry() async {
        let http = MockHTTPClient([.failure(URLError(.cancelled)), .response(status: 200, body: categoriesJSON)])
        await #expect(throws: CancellationError.self) {
            try await makeClient(http).send(.categories, as: [CategoryDTO].self)
        }
        #expect(await http.requests.count == 1)
    }
}
