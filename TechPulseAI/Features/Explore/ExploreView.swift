import SwiftUI

struct ExploreView: View {
    @State private var viewModel: ExploreViewModel
    @State private var searchText = ""
    @State private var searchPath: String?
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ExploreViewModel(dependencies: dependencies))
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppDestination.search(query: "")) {
                    Label("Search articles", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("explore.search")
            }
            switch viewModel.state {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading") }
            case let .failed(error):
                Section {
                    StateMessageView(title: error.title, message: error.message, systemImage: error.systemImage,
                                     actionTitle: error.actionTitle) { Task { await viewModel.load() } }
                }
            case .loaded, .empty:
                Section("Categories") {
                    ForEach(viewModel.categories) { category in
                        NavigationLink(value: AppDestination.category(category.id)) {
                            Label {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(category.title)
                                    Text(category.description).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: category.iconName).foregroundStyle(Palette.accent)
                            }
                        }
                        .accessibilityIdentifier("explore.category.\(category.id)")
                    }
                }
                if !viewModel.trendingTags.isEmpty {
                    Section("Trending technologies & tags") {
                        FlowTags(tags: viewModel.trendingTags)
                    }
                }
                Section {
                    ForEach(viewModel.sources) { source in
                        NavigationLink(value: AppDestination.source(source.id)) {
                            Label(source.name, systemImage: source.type == .rss ? "dot.radiowaves.up.forward" : "server.rack")
                        }
                    }
                } header: {
                    Text("Sources")
                } footer: {
                    if viewModel.isSampleData { Text("Sample sources for demonstration only.") }
                }
            }
        }
        .navigationTitle("Explore")
        .refreshable { await viewModel.load() }
        .task { if viewModel.categories.isEmpty { await viewModel.load() } }
    }
}

struct FlowTags: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(tags, id: \.self) { tag in
                    NavigationLink(value: AppDestination.search(query: tag)) {
                        Text("#\(tag)")
                            .font(.subheadline)
                            .padding(.horizontal, Spacing.m)
                            .frame(minHeight: Layout.minTouchTarget)
                            .background(Palette.chipBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search \(tag)")
                }
            }
        }
    }
}

/// Topic page for a category or source.
struct ArticleListScreen: View {
    @State private var viewModel: ArticleListViewModel

    init(kind: ArticleListViewModel.Kind, dependencies: AppDependencies) {
        _viewModel = State(initialValue: ArticleListViewModel(kind: kind, dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                switch viewModel.state {
                case .idle, .loading:
                    LoadingListView()
                case .empty:
                    StateMessageView(title: "No articles", message: "Nothing here yet.", systemImage: "tray")
                case let .failed(error):
                    StateMessageView(title: error.title, message: error.message, systemImage: error.systemImage,
                                     actionTitle: error.actionTitle) { Task { await viewModel.load() } }
                case .loaded:
                    if viewModel.visibleItems.isEmpty {
                        StateMessageView(title: "No matches", message: "No articles match these filters.",
                                         systemImage: "line.3.horizontal.decrease.circle", actionTitle: "Clear Filters") {
                            viewModel.difficulty = nil
                            viewModel.dateRange = .any
                        }
                    } else {
                        ArticleCardList(items: viewModel.visibleItems) { id in
                            Task { await viewModel.loadMoreIfNeeded(after: id) }
                        }
                    }
                    if viewModel.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading more")
                    } else if let error = viewModel.loadMoreError {
                        Button("Couldn’t load more — \(error.actionTitle ?? "Retry")") { Task { await viewModel.retryLoadMore() } }
                            .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                    }
                }
            }
            .padding(.vertical, Spacing.m)
            .frame(maxWidth: Layout.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.screenBackground)
        .navigationTitle(viewModel.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Date", selection: $viewModel.dateRange) {
                        ForEach(DateRangeFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Difficulty", selection: $viewModel.difficulty) {
                        Text("Any difficulty").tag(Difficulty?.none)
                        ForEach(Difficulty.allCases, id: \.self) { Text($0.title).tag(Difficulty?.some($0)) }
                    }
                } label: {
                    Label("Filters", systemImage: viewModel.hasActiveFilters
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityValue(viewModel.hasActiveFilters ? "Filters active" : "No filters")
            }
        }
        .refreshable { await viewModel.load() }
        .task { if viewModel.state.value == nil { await viewModel.load() } }
        .onChange(of: viewModel.dateRange) { Task { await viewModel.fillIfNeeded() } }
        .onChange(of: viewModel.difficulty) { Task { await viewModel.fillIfNeeded() } }
    }
}
