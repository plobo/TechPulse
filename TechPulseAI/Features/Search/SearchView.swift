import SwiftUI

struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @State private var showsFilters = false

    init(dependencies: AppDependencies, initialQuery: String = "") {
        _viewModel = State(initialValue: SearchViewModel(dependencies: dependencies, initialQuery: initialQuery))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                controls
                results
            }
            .padding(.vertical, Spacing.m)
            .frame(maxWidth: Layout.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.screenBackground)
        .navigationTitle("Search")
        .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Titles, sources, tags, summaries")
        .sheet(isPresented: $showsFilters) { SearchFiltersSheet(viewModel: viewModel) }
        .task { await viewModel.loadSources() }
        .task(id: viewModel.requestKey) {
            // Debounce typing; cancelled automatically when the key changes.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
    }

    private var controls: some View {
        HStack {
            Picker("Sort", selection: $viewModel.sort) {
                ForEach(ArticleSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("search.sort")
            Button {
                showsFilters = true
            } label: {
                Label("Filters", systemImage: viewModel.hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Layout.minTouchTarget, minHeight: Layout.minTouchTarget)
            }
            .accessibilityValue(viewModel.hasActiveFilters ? "Filters active" : "No filters")
            .accessibilityIdentifier("search.filters")
        }
        .padding(.horizontal, Spacing.l)
    }

    @ViewBuilder
    private var results: some View {
        switch viewModel.results {
        case .idle:
            StateMessageView(title: "Search TechPulse", message: "Find articles by title, source, tag or summary.",
                             systemImage: "magnifyingglass")
        case .loading:
            LoadingListView(count: 3)
        case .empty:
            StateMessageView(title: "No results", message: "Try different keywords or remove filters.",
                             systemImage: "doc.text.magnifyingglass",
                             actionTitle: viewModel.hasActiveFilters ? "Clear Filters" : nil) { viewModel.clearFilters() }
                .accessibilityIdentifier("search.empty")
        case let .failed(error):
            StateMessageView(title: error.title, message: error.message, systemImage: error.systemImage,
                             actionTitle: error.actionTitle) { Task { await viewModel.search() } }
        case let .loaded(articles):
            Text("\(articles.count) result\(articles.count == 1 ? "" : "s")")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, Spacing.l)
            ArticleCardList(items: articles.map { FeedItem(article: $0, reason: nil) })
                .accessibilityIdentifier("search.results")
        }
    }
}

struct SearchFiltersSheet: View {
    @Bindable var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $viewModel.categoryID) {
                    Text("All categories").tag(CategoryID?.none)
                    ForEach(ArticleCategory.builtIn) { Text($0.title).tag(CategoryID?.some($0.id)) }
                }
                Picker("Source", selection: $viewModel.sourceID) {
                    Text("All sources").tag(SourceID?.none)
                    ForEach(viewModel.sources) { Text($0.name).tag(SourceID?.some($0.id)) }
                }
                Picker("Date", selection: $viewModel.dateRange) {
                    ForEach(DateRangeFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Difficulty", selection: $viewModel.difficulty) {
                    Text("Any").tag(Difficulty?.none)
                    ForEach(Difficulty.allCases, id: \.self) { Text($0.title).tag(Difficulty?.some($0)) }
                }
                if viewModel.hasActiveFilters {
                    Button("Clear Filters", role: .destructive) { viewModel.clearFilters() }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
