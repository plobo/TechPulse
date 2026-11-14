import Foundation

struct ArticleCategory: Identifiable, Hashable, Sendable {
    let id: CategoryID
    let title: String
    let description: String
    let iconName: String

    /// The eight MVP categories, in display order.
    static let allIDs: [CategoryID] = [
        "ai-ml", "tech-news", "coding", "architecture", "ai-dev-tools", "research", "career", "tutorials",
    ]

    static let builtIn: [ArticleCategory] = [
        .init(id: "ai-ml", title: "AI & Machine Learning", description: "Models, training, inference and applied ML.", iconName: "brain"),
        .init(id: "tech-news", title: "Technology News", description: "Industry and platform news for developers.", iconName: "newspaper"),
        .init(id: "coding", title: "Coding & Programming", description: "Languages, frameworks and craft.", iconName: "chevron.left.forwardslash.chevron.right"),
        .init(id: "architecture", title: "Architecture & System Design", description: "Distributed systems, scaling and design.", iconName: "square.stack.3d.up"),
        .init(id: "ai-dev-tools", title: "AI Developer Tools", description: "Assistants, agents and AI-powered tooling.", iconName: "hammer"),
        .init(id: "research", title: "Research & Innovation", description: "Papers and emerging techniques.", iconName: "atom"),
        .init(id: "career", title: "Engineering Career", description: "Growth, leadership and teams.", iconName: "person.2"),
        .init(id: "tutorials", title: "Tutorials & Learning", description: "Hands-on guides and courses.", iconName: "graduationcap"),
    ]
}

enum SourceType: String, Sendable, Hashable, Codable {
    case rss, api
}

struct Source: Identifiable, Hashable, Sendable {
    let id: SourceID
    let name: String
    let homepageURL: URL
    let feedURL: URL?
    let type: SourceType
    let isEnabled: Bool
    /// Attribution text the publisher requires, shown alongside its content.
    let attribution: String?
}

struct DailyBriefing: Sendable, Hashable {
    let date: Date
    let articleIDs: [ArticleID]
    let introduction: String
    let keyThemes: [String]
    /// True only when the introduction was produced by an AI model (must then be labelled).
    let isAIGenerated: Bool
}
