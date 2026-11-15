import Foundation

/// One in-flight request per key, plus a sliding one-minute rate limit.
actor AIRequestGate {
    private let maxPerMinute: Int
    private let dateProvider: any DateProvider
    private var inFlight = Set<String>()
    private var starts: [Date] = []

    init(maxPerMinute: Int = 10, dateProvider: any DateProvider = SystemDateProvider()) {
        self.maxPerMinute = maxPerMinute
        self.dateProvider = dateProvider
    }

    func begin(_ key: String) throws {
        guard !inFlight.contains(key) else { throw AIServiceError.busy }
        let now = dateProvider.now
        starts.removeAll { now.timeIntervalSince($0) >= 60 }
        guard starts.count < maxPerMinute else { throw AIServiceError.rateLimited }
        starts.append(now)
        inFlight.insert(key)
    }

    func end(_ key: String) {
        inFlight.remove(key)
    }
}
