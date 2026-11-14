import Foundation
import Observation

enum LibrarySection: String, CaseIterable, Sendable {
    case bookmarks, history, notes

    var title: String { rawValue.capitalized }
}

enum ReadFilter: String, CaseIterable, Sendable {
    case all, unread, read

    var title: String { rawValue.capitalized }
}

struct NoteItem: Identifiable, Hashable, Sendable {
    let note: ArticleNote
    let article: Article?
    var id: UUID { note.id }
}

@MainActor
@Observable
final class LibraryViewModel {
    var section: LibrarySection = .bookmarks
    var readFilter: ReadFilter = .all
    var categoryID: CategoryID?
    private(set) var articles: [Article] = []
    private(set) var notes: [NoteItem] = []
    private(set) var isLoading = false

    private let dependencies: AppDependencies
    let library: LibraryStore

    init(dependencies: AppDependencies, library: LibraryStore) {
        self.dependencies = dependencies
        self.library = library
    }

    var visibleArticles: [Article] {
        articles.filter { article in
            let readOK: Bool = switch readFilter {
            case .all: true
            case .unread: !library.isRead(article.id)
            case .read: library.isRead(article.id)
            }
            return readOK && (categoryID.map { article.categoryIDs.contains($0) } ?? true)
        }
    }

    var visibleNotes: [NoteItem] {
        guard let categoryID else { return notes }
        return notes.filter { $0.article?.categoryIDs.contains(categoryID) ?? false }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let repo = dependencies.library
        do {
            switch section {
            case .bookmarks:
                articles = try await repo.cachedArticles(ids: try await repo.bookmarks().map(\.articleID))
            case .history:
                articles = try await repo.cachedArticles(ids: try await repo.history().map(\.articleID))
            case .notes:
                let all = try await repo.allNotes()
                let byID = Dictionary(try await repo.cachedArticles(ids: Array(Set(all.map(\.articleID)))).map { ($0.id, $0) },
                                      uniquingKeysWith: { a, _ in a })
                notes = all.map { NoteItem(note: $0, article: byID[$0.articleID]) }
            }
        } catch {
            library.lastErrorMessage = "Couldn’t load your library."
        }
    }

    func removeBookmark(_ id: ArticleID) async {
        await library.removeBookmark(id)
        articles.removeAll { $0.id == id }
    }

    func clearHistory() async {
        await library.clearHistory()
        if section == .history { articles = [] }
    }

    func deleteNote(_ item: NoteItem) async {
        await library.deleteNote(item.note.id)
        notes.removeAll { $0.id == item.id }
    }
}
