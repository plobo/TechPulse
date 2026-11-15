import SwiftUI

struct ArticleDetailView: View {
    @State private var viewModel: ArticleDetailViewModel
    @State private var isEditingNote = false
    @State private var editingNote: ArticleNote?
    @State private var isReporting = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dependencies) private var dependencies

    init(articleID: ArticleID, dependencies: AppDependencies, library: LibraryStore) {
        _viewModel = State(initialValue: ArticleDetailViewModel(articleID: articleID, dependencies: dependencies, library: library))
    }

    var body: some View {
        Group {
            switch viewModel.article {
            case .idle, .loading, .empty:
                LoadingListView(count: 2)
            case let .failed(error):
                StateMessageView(title: error.title, message: error.message, systemImage: error.systemImage,
                                 actionTitle: error.actionTitle) { Task { await viewModel.load() } }
            case let .loaded(article):
                content(article)
            }
        }
        .background(Palette.screenBackground)
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel.article.value == nil { await viewModel.load() } }
        .toolbar { toolbar }
        .sheet(isPresented: $isEditingNote) {
            NoteEditorSheet(initialText: editingNote?.text ?? "") { text in
                await viewModel.saveNote(id: editingNote?.id, text: text)
                return viewModel.noteError == nil
            }
        }
        .sheet(isPresented: $isReporting) {
            if let article = viewModel.article.value { ReportIssueSheet(article: article) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let article = viewModel.article.value {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.toggleBookmark() }
                } label: {
                    Label(viewModel.isBookmarked ? "Remove Bookmark" : "Bookmark",
                          systemImage: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .accessibilityIdentifier("detail.bookmark")
                ShareLink(item: article.canonicalURL, subject: Text(article.title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Menu {
                    Button { editingNote = nil; isEditingNote = true } label: { Label("Add Note", systemImage: "note.text.badge.plus") }
                    Button { isReporting = true } label: { Label("Report a Problem", systemImage: "exclamationmark.bubble") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("detail.more")
            }
        }
    }

    private func content(_ article: Article) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header(article)
                if viewModel.isShowingOfflineCopy {
                    Label("Showing your saved offline copy.", systemImage: "arrow.down.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if dependencies.isSampleData { SampleDataBadge() }
                if let summary = article.summary {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Summary").font(.headline).accessibilityAddTraits(.isHeader)
                        Text(summary).font(Typography.articleBody)
                        Text("Provided with the source metadata.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                articleBody(article)
                openOriginalButton(article)
                ArticleAISection(article: article, dependencies: dependencies, library: viewModel.library)
                if !article.tags.isEmpty { tags(article) }
                notesSection
                if !viewModel.related.isEmpty { relatedSection }
            }
            .padding(Spacing.l)
            .frame(maxWidth: Layout.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("article.detail")
    }

    private func header(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let category = ArticleFormatting.categoryTitle(article.categoryIDs.first) {
                Text(category.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
            }
            Text(article.title).font(Typography.articleTitle).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                NavigationLink(value: AppDestination.source(article.sourceID)) {
                    Text(article.sourceName).font(.subheadline.weight(.semibold))
                }
                .accessibilityHint("Shows more from this source")
                let meta = [article.author.map { "By \($0)" }, ArticleFormatting.absoluteDate(article.publishedAt),
                            ArticleFormatting.readingTime(article.readingTimeMinutes), article.difficulty?.title]
                    .compactMap { $0 }.joined(separator: " · ")
                if !meta.isEmpty { Text(meta).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder
    private func articleBody(_ article: Article) -> some View {
        switch ArticleBodyPolicy.body(for: article) {
        case let .full(text):
            Text(text).font(Typography.articleBody).lineSpacing(4).textSelection(.enabled)
        case let .excerpt(text):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(text).font(Typography.articleBody).lineSpacing(4)
                Text("Excerpt shown with permission. Read the full article at \(article.sourceName).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .linkOnly:
            Text("This publisher shares headlines only. Open the original to read the article.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func openOriginalButton(_ article: Article) -> some View {
        Button {
            openURL(article.canonicalURL)
        } label: {
            Label("Read at \(article.sourceName)", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Opens \(article.canonicalURL.host() ?? "the publisher") in your browser")
        .accessibilityIdentifier("detail.openOriginal")
    }

    private func tags(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Topics").font(.headline).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(article.tags, id: \.self) { tag in
                        NavigationLink(value: AppDestination.search(query: tag)) {
                            Text("#\(tag)").font(.subheadline)
                                .padding(.horizontal, Spacing.m)
                                .frame(minHeight: Layout.minTouchTarget)
                                .background(Palette.chipBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Your notes").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { editingNote = nil; isEditingNote = true } label: { Label("Add Note", systemImage: "plus") }
                    .accessibilityIdentifier("detail.addNote")
            }
            if viewModel.notes.isEmpty {
                Text("Notes stay on this device and are never sent to AI providers.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(viewModel.notes) { note in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(note.text)
                    Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                .cardStyle()
                .contextMenu {
                    Button("Edit") { editingNote = note; isEditingNote = true }
                    Button("Delete", role: .destructive) { Task { await viewModel.deleteNote(note) } }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Edit") { editingNote = note; isEditingNote = true }
                .accessibilityAction(named: "Delete") { Task { await viewModel.deleteNote(note) } }
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Related").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(viewModel.related) { related in
                NavigationLink(value: AppDestination.article(related.id)) {
                    ArticleCardView(article: related)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NoteEditorSheet: View {
    @State private var text: String
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    let onSave: (String) async -> Bool

    init(initialText: String, onSave: @escaping (String) async -> Bool) {
        _text = State(initialValue: initialText)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .focused($focused)
                        .accessibilityLabel("Note text")
                        .accessibilityIdentifier("note.editor")
                } footer: {
                    Text(error ?? "Saved on this device only.")
                        .foregroundStyle(error == nil ? Color.secondary : Color.red)
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            if await onSave(text) { dismiss() } else { error = "A note can’t be empty." }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("note.save")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Builds a problem report the user sends themselves (no backend report endpoint yet).
struct ReportIssueSheet: View {
    enum Reason: String, CaseIterable, Identifiable {
        case wrongTitle = "Incorrect title"
        case wrongDate = "Incorrect date"
        case wrongSource = "Wrong source or author"
        case brokenLink = "Broken link"
        case badSummary = "Inaccurate summary"
        case other = "Other"
        var id: String { rawValue }
    }

    let article: Article
    @State private var reason: Reason = .wrongTitle
    @State private var details = ""
    @Environment(\.dismiss) private var dismiss

    var reportText: String {
        """
        TechPulse AI problem report
        Reason: \(reason.rawValue)
        Article ID: \(article.id)
        Title: \(article.title)
        Source: \(article.sourceName)
        URL: \(article.canonicalURL.absoluteString)
        Details: \(details.isEmpty ? "—" : details)
        """
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("What’s wrong?", selection: $reason) {
                    ForEach(Reason.allCases) { Text($0.rawValue).tag($0) }
                }
                Section("Details (optional)") {
                    TextField("Describe the problem", text: $details, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    ShareLink(item: reportText) { Label("Send Report…", systemImage: "paperplane") }
                } footer: {
                    Text("The report includes only the article details above. It does not include your notes or history.")
                }
            }
            .navigationTitle("Report a Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
