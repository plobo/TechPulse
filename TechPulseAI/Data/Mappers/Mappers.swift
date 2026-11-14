import Foundation

enum MappingError: Error, Equatable {
    case invalidURL(String)
}

enum ArticleMapper {
    static func map(_ dto: ArticleDTO, fetchedAt: Date) throws -> Article {
        guard let url = WebURL.validated(dto.canonicalURL) else { throw MappingError.invalidURL(dto.canonicalURL) }
        let availability: ContentAvailability = switch dto.contentAvailability {
        case "full": .full
        case "excerpt_only": .excerptOnly
        default: .linkOnly
        }
        let content = availability == .full ? dto.content : nil
        return Article(
            id: dto.id,
            canonicalURL: url,
            title: dto.title,
            summary: dto.summary.nonEmpty,
            excerpt: dto.excerpt.nonEmpty,
            content: content.nonEmpty,
            imageURL: dto.imageURL.flatMap(WebURL.validated),
            sourceID: dto.sourceID,
            sourceName: dto.sourceName,
            author: dto.author.nonEmpty,
            publishedAt: dto.publishedAt,
            fetchedAt: fetchedAt,
            categoryIDs: dto.categoryIDs ?? [],
            tags: dto.tags ?? [],
            readingTimeMinutes: dto.readingTimeMinutes ?? (content ?? dto.excerpt).flatMap(ReadingTimeEstimator.minutes),
            contentAvailability: availability,
            difficulty: dto.difficulty.flatMap(Difficulty.init(rawValue:))
        )
    }

    /// Maps a page, dropping (not failing on) individual malformed items.
    static func map(_ dto: ArticlePageDTO, fetchedAt: Date) -> ArticlePage {
        ArticlePage(articles: dto.items.compactMap { try? map($0, fetchedAt: fetchedAt) }, nextCursor: dto.nextCursor)
    }
}

enum CatalogMapper {
    static func map(_ dto: CategoryDTO) -> ArticleCategory {
        let builtIn = ArticleCategory.builtIn.first { $0.id == dto.id }
        return ArticleCategory(id: dto.id, title: dto.title,
                               description: dto.description ?? builtIn?.description ?? "",
                               iconName: dto.icon ?? builtIn?.iconName ?? "tag")
    }

    static func map(_ dto: SourceDTO) -> Source? {
        guard let home = WebURL.validated(dto.homepageURL) else { return nil }
        return Source(id: dto.id, name: dto.name, homepageURL: home,
                      feedURL: dto.feedURL.flatMap(WebURL.validated),
                      type: SourceType(rawValue: dto.type ?? "") ?? .rss,
                      isEnabled: dto.enabled ?? true, attribution: dto.attribution)
    }

    static func map(_ dto: DailyBriefingDTO) -> DailyBriefing {
        DailyBriefing(date: dto.date, articleIDs: dto.articleIDs, introduction: dto.introduction,
                      keyThemes: dto.keyThemes ?? [], isAIGenerated: dto.isAIGenerated ?? false)
    }
}

enum WebURL {
    /// Only absolute http(s) URLs with a host are accepted (no javascript:, file:, etc.).
    static func validated(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
