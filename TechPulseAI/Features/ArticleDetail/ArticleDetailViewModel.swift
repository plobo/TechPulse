import Foundation
import Observation

/// What the reader is allowed to show for an article, per publisher terms.
enum ArticleBody: Equatable, Sendable {
    case full(String)
    case excerpt(String)
    case linkOnly
}

enum ArticleBodyPolicy {
    static func body(for article: Article) -> ArticleBody {
        switch article.contentAvailability {
        case .full:
            if let content = article.content { return .full(content) }
            return article.excerpt.map(ArticleBody.excerpt) ?? .linkOnly
        case .excerptOnly:
            return article.excerpt.map(ArticleBody.excerpt) ?? .linkOnly
        case .linkOnly:
            return .linkOnly
        }
    }
}

@MainActor
@Observable
final class ArticleDetailViewModel {
    let articleID: ArticleID
    private(set) var article: LoadState<Article> = .idle
    private(set) var related: [Article] = []
    private(set) var notes: [ArticleNote] = []
    private(set) var isShowingOfflineCopy = false
    var noteError: String?

    private let dependencies: AppDependencies
    let library: LibraryStore

    init(articleID: ArticleID, dependencies: AppDependencies, library: LibraryStore) {
        self.articleID = articleID
        self.dependencies = dependencies
        self.library = library
    }

    var isBookmarked: Bool { library.isBookmarked(articleID) }
    var isAIAvailable: Bool { false }

    func load() async {
        if article.value == nil { article = .loading }
        let loaded: Article
        do {
            loaded = try await dependencies.articles.article(id: articleID)
            isShowingOfflineCopy = false
        } catch is CancellationError {
            return
        } catch {
            if let cached = try? await dependencies.library.cachedArticles(ids: [articleID]).first {
                loaded = cached
                isShowingOfflineCopy = true
            } else {
                article = .failed(UserFacingError(error))
                return
            }
        }
        article = .loaded(loaded)
        await library.recordOpen(loaded)
        notes = (try? await dependencies.library.notes(for: articleID)) ?? []
        related = (try? await dependencies.articles.relatedArticles(to: loaded, limit: 5)) ?? []
    }

    func toggleBookmark() async {
        guard let value = article.value else { return }
        await library.toggleBookmark(value)
    }

    func saveNote(id: UUID? = nil, text: String) async {
        do {
            try await library.saveNote(id: id, articleID: articleID, text: text)
            noteError = nil
            notes = (try? await dependencies.library.notes(for: articleID)) ?? notes
        } catch LibraryError.emptyNote {
            noteError = "A note can’t be empty."
        } catch {
            noteError = "Couldn’t save your note."
        }
    }

    func deleteNote(_ note: ArticleNote) async {
        if await library.deleteNote(note.id) { notes.removeAll { $0.id == note.id } }
    }
}
