import SwiftUI

/// Article page AI section: summaries plus entry points to Ask, Explain code and Diagram.
struct ArticleAISection: View {
    @State private var viewModel: ArticleAIViewModel
    @State private var sheet: Sheet?
    private let dependencies: AppDependencies
    private let library: LibraryStore

    enum Sheet: String, Identifiable {
        case ask, code, diagram
        var id: String { rawValue }
    }

    init(article: Article, dependencies: AppDependencies, library: LibraryStore) {
        self.dependencies = dependencies
        self.library = library
        _viewModel = State(initialValue: ArticleAIViewModel(article: article, dependencies: dependencies, library: library))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("AI summary", systemImage: "wand.and.stars").font(.headline).accessibilityAddTraits(.isHeader)
            if viewModel.isEnabled {
                Picker("Summary length", selection: $viewModel.selectedType) {
                    ForEach(SummaryType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ai.summary.type")
                summaryContent
                Divider()
                actions
            } else {
                Text(disabledMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.summary.panel")
        .task { await viewModel.load() }
        .onDisappear { viewModel.cancel() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .ask: AskArticleSheet(article: viewModel.article, dependencies: dependencies, library: library)
            case .code: CodeExplainerSheet(article: viewModel.article, dependencies: dependencies, library: library)
            case .diagram: DiagramSheet(article: viewModel.article, dependencies: dependencies, library: library)
            }
        }
    }

    private var disabledMessage: String {
        guard let availability = viewModel.availability else { return "Checking on-device AI…" }
        if availability != .available { return availability.message + " Reading, notes and bookmarks work without AI." }
        return "Turn on AI features in Profile to get on-device summaries, Q&A and diagrams."
    }

    @ViewBuilder
    private var summaryContent: some View {
        let type = viewModel.selectedType
        switch viewModel.current {
        case .idle:
            Button {
                Task { await viewModel.generate(type) }
            } label: {
                Label("Summarize (\(type.title))", systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("ai.summary.generate")
        case .loading:
            HStack {
                ProgressView()
                Text("Summarizing on device…").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { viewModel.cancel() }
            }
            .accessibilityElement(children: .combine)
        case let .loaded(artifact):
            VStack(alignment: .leading, spacing: Spacing.s) {
                AILabelsRow(provider: artifact.provider, basis: artifact.basis, isSampleData: viewModel.isSampleData)
                Text(artifact.text ?? "")
                    .font(Typography.articleBody)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("ai.summary.text")
                HStack {
                    Button { Task { await viewModel.generate(type, force: true) } } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    ShareLink(item: AIReport.text(for: artifact)) { Label("Report a Problem", systemImage: "exclamationmark.bubble") }
                }
                .font(.footnote)
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label(message, systemImage: "exclamationmark.triangle").font(.footnote)
                Button("Try Again") { Task { await viewModel.generate(type, force: true) } }
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack { actionButtons }
            VStack(alignment: .leading) { actionButtons }
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
    }

    @ViewBuilder private var actionButtons: some View {
        Button { sheet = .ask } label: { Label("Ask AI", systemImage: "bubble.left.and.text.bubble.right") }
            .accessibilityIdentifier("ai.ask")
        Button { sheet = .code } label: { Label("Explain Code", systemImage: "curlybraces") }
            .accessibilityIdentifier("ai.code")
        Button { sheet = .diagram } label: { Label("Diagram", systemImage: "point.3.connected.trianglepath.dotted") }
            .accessibilityIdentifier("ai.diagram")
    }
}
