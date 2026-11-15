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
    /// Debug-only: use the Demo AI stand-in instead of the real model.
    var demoAIEnabled = false
    /// Count of successful local AI generations (shown in Settings).
    var aiGenerationCount = 0

    static let `default` = UserPreferences()

    init() {}

    /// Tolerant decoding so payloads saved by older versions keep working.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserPreferences()
        selectedCategoryIDs = try c.decodeIfPresent([CategoryID].self, forKey: .selectedCategoryIDs) ?? d.selectedCategoryIDs
        followedTechnologies = try c.decodeIfPresent([String].self, forKey: .followedTechnologies) ?? d.followedTechnologies
        preferredSummaryLength = try c.decodeIfPresent(SummaryLength.self, forKey: .preferredSummaryLength) ?? d.preferredSummaryLength
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? d.theme
        notifications = try c.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? d.notifications
        aiFeaturesEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiFeaturesEnabled) ?? d.aiFeaturesEnabled
        personalizationEnabled = try c.decodeIfPresent(Bool.self, forKey: .personalizationEnabled) ?? d.personalizationEnabled
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        demoAIEnabled = try c.decodeIfPresent(Bool.self, forKey: .demoAIEnabled) ?? d.demoAIEnabled
        aiGenerationCount = try c.decodeIfPresent(Int.self, forKey: .aiGenerationCount) ?? d.aiGenerationCount
    }
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
    /// On-device AI history; absent in exports from before Milestone 4.
    var ai: [AIActivityItem]?
}
