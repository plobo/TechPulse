import Foundation

/// Builds a deterministic (non-AI) daily briefing from article metadata.
enum DailyBriefingBuilder {
    static func build(from articles: [Article], now: Date, window: TimeInterval = 48 * 3600, maxArticles: Int = 5) -> DailyBriefing {
        let recent = ArticleSort.newest.sorted(
            articles.filter { guard let date = $0.publishedAt else { return false }
                return date <= now && now.timeIntervalSince(date) <= window },
            query: ""
        )

        // Round-robin by primary category for diversity, newest first.
        var picked: [Article] = []
        var usedCategories = Set<CategoryID>()
        for article in recent where picked.count < maxArticles {
            let primary = article.categoryIDs.first ?? ""
            if !usedCategories.contains(primary) {
                picked.append(article)
                usedCategories.insert(primary)
            }
        }
        for article in recent where picked.count < maxArticles && !picked.contains(article) {
            picked.append(article)
        }

        var counts: [String: Int] = [:]
        for tag in recent.flatMap(\.tags) { counts[tag.lowercased(), default: 0] += 1 }
        let themes = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(5).map(\.key)

        let intro: String
        if picked.isEmpty {
            intro = "No new articles in the last \(Int(window / 3600)) hours. Check back later."
        } else {
            let themeText = themes.prefix(3).joined(separator: ", ")
            intro = "\(picked.count) highlights from \(Set(picked.map(\.sourceName)).count) sources"
                + (themeText.isEmpty ? "." : ". Trending: \(themeText).")
        }
        return DailyBriefing(date: now, articleIDs: picked.map(\.id), introduction: intro, keyThemes: Array(themes), isAIGenerated: false)
    }
}
