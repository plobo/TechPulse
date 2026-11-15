import Foundation

/// Provider-neutral AI abstraction (reshaped in Task 3).
protocol AIService: Sendable {
    var isAvailable: Bool { get }
}

struct UnavailableAIService: AIService {
    var isAvailable: Bool { false }
}
