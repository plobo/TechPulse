import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    var body: some View {
        LibraryContent(viewModel: LibraryViewModel(dependencies: dependencies, library: library))
    }
}

private struct LibraryContent: View {
    @State var viewModel: LibraryViewModel
    @State private var confirmClearHistory = false

    var body: some View {
        List {
            Section {
                Picker("Section", selection: $viewModel.section) {
                    ForEach(LibrarySection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("library.section")
                .listRowBackground(Color.clear)
            }
            content
        }
        .navigationTitle("Library")
        .toolbar { toolbar }
        .task(id: "\(viewModel.section.rawValue)-\(viewModel.library.revision)") { await viewModel.load() }
        .confirmationDialog("Clear reading history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { Task { await viewModel.clearHistory() } }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if viewModel.section != .notes {
                    Picker("Show", selection: $viewModel.readFilter) {
                        ForEach(ReadFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Picker("Category", selection: $viewModel.categoryID) {
                    Text("All categories").tag(CategoryID?.none)
                    ForEach(ArticleCategory.builtIn) { Text($0.title).tag(CategoryID?.some($0.id)) }
                }
                if viewModel.section == .history {
                    Divider()
                    Button("Clear History", role: .destructive) { confirmClearHistory = true }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .accessibilityIdentifier("library.filter")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.section {
        case .bookmarks, .history:
            if viewModel.visibleArticles.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(viewModel.visibleArticles) { article in
                        NavigationLink(value: AppDestination.article(article.id)) {
                            LibraryRow(article: article, isRead: viewModel.library.isRead(article.id))
                        }
                        .swipeActions {
                            if viewModel.section == .bookmarks {
                                Button("Remove", role: .destructive) { Task { await viewModel.removeBookmark(article.id) } }
                            }
                        }
                    }
                } footer: {
                    Label("Saved metadata is available offline.", systemImage: "arrow.down.circle")
                }
            }
        case .notes:
            if viewModel.visibleNotes.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.visibleNotes) { item in
                    NavigationLink(value: AppDestination.article(item.note.articleID)) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(item.note.text).lineLimit(4)
                            Text(item.article?.title ?? "Article unavailable offline")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await viewModel.deleteNote(item) } }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        let (title, message, icon): (String, String, String) = switch viewModel.section {
        case .bookmarks: ("No bookmarks", "Tap the bookmark button on any article to save it here.", "bookmark")
        case .history: ("No reading history", "Articles you open will appear here.", "clock")
        case .notes: ("No notes", "Add notes from an article’s detail page.", "note.text")
        }
        return StateMessageView(title: title, message: message, systemImage: icon)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("library.empty")
    }
}

private struct LibraryRow: View {
    let article: Article
    let isRead: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(article.title).font(.headline)
                HStack(spacing: Spacing.s) {
                    Text(article.sourceName)
                    if let category = ArticleFormatting.categoryTitle(article.categoryIDs.first) { Text(category) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Available offline")
            if !isRead {
                Text("Unread").font(.caption2.weight(.semibold)).padding(4)
                    .background(Palette.chipBackground, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}
