import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

enum APIError: Error, Equatable, Sendable {
    case offline
    case http(status: Int)
    case transport(URLError.Code)
    case decoding
    case invalidResponse

    var isTransient: Bool {
        switch self {
        case let .http(status): status == 408 || status == 429 || (500...599).contains(status)
        case let .transport(code): RetryPolicy.transientURLErrors.contains(code)
        default: false
        }
    }
}

struct RetryPolicy: Sendable {
    var maxAttempts: Int = 3
    var baseDelay: Duration = .milliseconds(500)
    var maxDelay: Duration = .seconds(8)

    static let transientURLErrors: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
    ]

    /// Exponential backoff: base * 2^(attempt-1), capped at maxDelay.
    func delay(afterAttempt attempt: Int) -> Duration {
        let factor = 1 << min(max(attempt - 1, 0), 20)
        return min(baseDelay * factor, maxDelay)
    }
}

struct Endpoint: Sendable, Hashable {
    var path: String
    var queryItems: [URLQueryItem] = []

    static func articles(category: CategoryID?, source: SourceID? = nil, cursor: String?, limit: Int) -> Endpoint {
        Endpoint(path: "/v1/articles", queryItems: [
            category.map { URLQueryItem(name: "category", value: $0) },
            source.map { URLQueryItem(name: "source", value: $0) },
            cursor.map { URLQueryItem(name: "cursor", value: $0) },
            URLQueryItem(name: "limit", value: String(limit)),
        ].compactMap { $0 })
    }

    static func article(id: ArticleID) -> Endpoint {
        Endpoint(path: "/v1/articles/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? id)")
    }

    static func search(_ query: SearchQuery) -> Endpoint {
        let iso = Date.ISO8601FormatStyle()
        return Endpoint(path: "/v1/search", queryItems: [
            URLQueryItem(name: "q", value: query.trimmedText),
            query.categoryID.map { URLQueryItem(name: "category", value: $0) },
            query.sourceID.map { URLQueryItem(name: "source", value: $0) },
            query.from.map { URLQueryItem(name: "from", value: iso.format($0)) },
            query.to.map { URLQueryItem(name: "to", value: iso.format($0)) },
            query.difficulty.map { URLQueryItem(name: "difficulty", value: $0.rawValue) },
            URLQueryItem(name: "sort", value: query.sort.rawValue),
        ].compactMap { $0 })
    }

    static let categories = Endpoint(path: "/v1/categories")
    static let sources = Endpoint(path: "/v1/sources")
    static let dailyBriefing = Endpoint(path: "/v1/briefings/daily")
}

/// Bounded ETag cache so 304 Not Modified responses can reuse the last body.
actor ETagCache {
    private var entries: [URL: (etag: String, body: Data)] = [:]
    private var order: [URL] = []
    private let capacity: Int

    init(capacity: Int = 64) { self.capacity = capacity }

    func entry(for url: URL) -> (etag: String, body: Data)? { entries[url] }

    func store(etag: String, body: Data, for url: URL) {
        if entries[url] == nil { order.append(url) }
        entries[url] = (etag, body)
        while order.count > capacity { entries[order.removeFirst()] = nil }
    }
}

struct APIClient: Sendable {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    let baseURL: URL
    let http: any HTTPClient
    var retryPolicy = RetryPolicy()
    var timeout: TimeInterval = 15
    var sleep: Sleep = { try await Task.sleep(for: $0) }
    private let etags = ETagCache()

    init(baseURL: URL, http: any HTTPClient, retryPolicy: RetryPolicy = RetryPolicy(),
         timeout: TimeInterval = 15, sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.baseURL = baseURL
        self.http = http
        self.retryPolicy = retryPolicy
        self.timeout = timeout
        self.sleep = sleep
    }

    func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidResponse }
        comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + endpoint.path
        comps.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems
        guard let url = comps.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await fetch(endpoint)
        do {
            return try JSONDecoder.techPulse.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func fetch(_ endpoint: Endpoint) async throws -> Data {
        var request = try makeRequest(endpoint)
        let url = request.url!
        let cached = await etags.entry(for: url)
        if let cached { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            do {
                return try await perform(request, cached: cached?.body)
            } catch let error as APIError where error.isTransient && attempt < retryPolicy.maxAttempts {
                try await sleep(retryPolicy.delay(afterAttempt: attempt))
            }
        }
    }

    private func perform(_ request: URLRequest, cached: Data?) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await http.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: throw APIError.offline
            default: throw APIError.transport(error.code)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200...299:
            if let etag = http.value(forHTTPHeaderField: "ETag"), let url = request.url {
                await etags.store(etag: etag, body: data, for: url)
            }
            return data
        case 304:
            guard let cached else { throw APIError.invalidResponse }
            return cached
        default:
            throw APIError.http(status: http.statusCode)
        }
    }
}
