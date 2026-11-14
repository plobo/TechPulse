import Foundation

enum ArticleFormatting {
    static func readingTime(_ minutes: Int?) -> String? {
        minutes.map { "\($0) min read" }
    }

    static func relativeDate(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func absoluteDate(_ date: Date?) -> String? {
        date?.formatted(date: .abbreviated, time: .shortened)
    }

    static func categoryTitle(_ id: CategoryID?) -> String? {
        guard let id else { return nil }
        return ArticleCategory.builtIn.first { $0.id == id }?.title ?? id
    }

    /// Single VoiceOver sentence for an article card.
    static func accessibilityLabel(for article: Article, now: Date, isBookmarked: Bool, isRead: Bool, reason: String? = nil) -> String {
        [
            article.title,
            "from \(article.sourceName)",
            relativeDate(article.publishedAt, now: now),
            categoryTitle(article.categoryIDs.first),
            readingTime(article.readingTimeMinutes),
            isBookmarked ? "Bookmarked" : nil,
            isRead ? "Read" : "Unread",
            reason,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
