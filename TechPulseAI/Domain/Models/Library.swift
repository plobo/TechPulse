import Foundation

struct Bookmark: Hashable, Sendable, Codable {
    let articleID: ArticleID
    let createdAt: Date
}

struct ArticleNote: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let articleID: ArticleID
    let text: String
    let createdAt: Date
    let updatedAt: Date
}

struct ReadingHistoryEntry: Hashable, Sendable, Codable {
    let articleID: ArticleID
    let lastOpenedAt: Date
    let openCount: Int
}

enum AppTheme: String, Sendable, Codable, CaseIterable {
    case system, light, dark

    var title: String { rawValue.capitalized }
}

enum SummaryLength: String, Sendable, Codable, CaseIterable {
    case thirtySeconds, twoMinutes, detailed

    var title: String {
        switch self {
        case .thirtySeconds: "30-second"
        case .twoMinutes: "2-minute"
        case .detailed: "Detailed"
        }
    }
}

struct NotificationSettings: Hashable, Sendable, Codable {
    var digestEnabled = false
    var topicAlertsEnabled = false
    /// Hour-of-day (0–23) quiet hours window.
    var quietHoursStart = 22
    var quietHoursEnd = 7
}

struct UserPreferences: Hashable, Sendable, Codable {
    var selectedCategoryIDs: [CategoryID] = []
    var followedTechnologies: [String] = []
    var preferredSummaryLength: SummaryLength = .twoMinutes
    var theme: AppTheme = .system
    var notifications = NotificationSettings()
    /// AI features are opt-in.
    var aiFeaturesEnabled = false
    var personalizationEnabled = true
    var hasCompletedOnboarding = false

    static let `default` = UserPreferences()
}

enum LibraryError: Error, Equatable {
    case emptyNote
    case noteNotFound
}

/// Portable JSON export of on-device user data.
struct LibraryExport: Codable, Sendable {
    let exportedAt: Date
    let bookmarks: [Bookmark]
    let notes: [ArticleNote]
    let history: [ReadingHistoryEntry]
    let preferences: UserPreferences
}
