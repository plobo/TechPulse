import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Sendable {
    case discover, explore, aiReader, library, profile

    var title: String {
        switch self {
        case .discover: "Discover"
        case .explore: "Explore"
        case .aiReader: "AI Reader"
        case .library: "Library"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles.rectangle.stack"
        case .explore: "safari"
        case .aiReader: "brain"
        case .library: "books.vertical"
        case .profile: "person.crop.circle"
        }
    }
}

/// Typed navigation destinations shared by every tab's NavigationStack.
enum AppDestination: Hashable, Sendable {
    case article(ArticleID)
    case category(CategoryID)
    case source(SourceID)
    case search(query: String)
    case dailyBriefing
    case privacy
    case sourcePolicy
    case about
}
