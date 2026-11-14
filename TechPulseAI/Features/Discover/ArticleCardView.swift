import SwiftUI

struct ArticleCardView: View {
    let article: Article
    var reason: String?
    var now: Date = .now
    @Environment(LibraryStore.self) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isBookmarked = library.isBookmarked(article.id)
        let isRead = library.isRead(article.id)
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if let category = ArticleFormatting.categoryTitle(article.categoryIDs.first) {
                    Text(category.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
                Text(article.title)
                    .font(Typography.cardTitle)
                    .foregroundStyle(isRead ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                if let summary = article.summary, !dynamicTypeSize.isAccessibilitySize {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                metaRow(isBookmarked: isBookmarked, isRead: isRead)
                if let reason {
                    Label(reason, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let imageURL = article.imageURL, !dynamicTypeSize.isAccessibilitySize {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Palette.chipBackground
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            }
        }
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ArticleFormatting.accessibilityLabel(for: article, now: now, isBookmarked: isBookmarked, isRead: isRead,
                                                                   reason: reason))
        .accessibilityHint("Opens the article")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: isBookmarked ? "Remove bookmark" : "Bookmark") {
            Task { await library.toggleBookmark(article) }
        }
        .accessibilityIdentifier("article.card.\(article.id)")
    }

    @ViewBuilder
    private func metaRow(isBookmarked: Bool, isRead: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) { metaItems(isBookmarked: isBookmarked, isRead: isRead) }
            VStack(alignment: .leading, spacing: Spacing.xs) { metaItems(isBookmarked: isBookmarked, isRead: isRead) }
        }
        .font(Typography.meta)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func metaItems(isBookmarked: Bool, isRead: Bool) -> some View {
        Text(article.sourceName).fontWeight(.medium)
        if let date = ArticleFormatting.relativeDate(article.publishedAt, now: now) { Text(date) }
        if let time = ArticleFormatting.readingTime(article.readingTimeMinutes) { Text(time) }
        if isBookmarked { Image(systemName: "bookmark.fill") }
        if isRead { Image(systemName: "checkmark.circle") }
    }
}

/// Navigable list of article cards used by Explore, search, topic and library lists.
struct ArticleCardList: View {
    let items: [FeedItem]
    var onAppearLast: ((ArticleID) -> Void)?

    var body: some View {
        LazyVStack(spacing: Spacing.m) {
            ForEach(items) { item in
                NavigationLink(value: AppDestination.article(item.article.id)) {
                    ArticleCardView(article: item.article, reason: item.reason)
                }
                .buttonStyle(.plain)
                .onAppear { onAppearLast?(item.article.id) }
            }
        }
        .padding(.horizontal, Spacing.l)
    }
}
