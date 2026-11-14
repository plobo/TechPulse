import SwiftUI

struct DiscoverView: View {
    @State private var viewModel: DiscoverViewModel
    @Environment(LibraryStore.self) private var library

    init(dependencies: AppDependencies, library: LibraryStore) {
        _viewModel = State(initialValue: DiscoverViewModel(dependencies: dependencies, library: library))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if viewModel.isSampleData {
                    SampleDataBanner().padding(.horizontal, Spacing.l)
                }
                if let briefing = viewModel.briefing {
                    NavigationLink(value: AppDestination.dailyBriefing) {
                        DailyBriefingCard(briefing: briefing, articles: viewModel.briefingArticles)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Spacing.l)
                }
                if let error = viewModel.refreshError {
                    Label("Couldn’t refresh — \(error.title.lowercased()). Showing earlier results.", systemImage: error.systemImage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.l)
                        .accessibilityIdentifier("discover.refreshError")
                }
                categoryChips
                if !viewModel.trendingTopics.isEmpty { trending }
                feedContent
            }
            .padding(.vertical, Spacing.m)
            .frame(maxWidth: Layout.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.screenBackground)
        .navigationTitle("Discover")
        .refreshable { await viewModel.load() }
        .task { if viewModel.feed.value == nil { await viewModel.load() } }
        .onChange(of: library.preferences) { viewModel.applyPreferences() }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ChipView(title: "For You", systemImage: "sparkles", isSelected: viewModel.selectedCategoryID == nil) {
                    Task { await viewModel.select(category: nil) }
                }
                .accessibilityIdentifier("chip.all")
                ForEach(viewModel.categories) { category in
                    ChipView(title: category.title, systemImage: category.iconName,
                             isSelected: viewModel.selectedCategoryID == category.id) {
                        Task { await viewModel.select(category: category.id) }
                    }
                    .accessibilityIdentifier("chip.\(category.id)")
                }
            }
            .padding(.horizontal, Spacing.l)
        }
        .accessibilityLabel("Categories")
    }

    private var trending: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Trending topics").font(Typography.sectionHeader).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(viewModel.trendingTopics, id: \.self) { topic in
                        NavigationLink(value: AppDestination.search(query: topic)) {
                            Text("#\(topic)")
                                .font(.subheadline)
                                .padding(.horizontal, Spacing.m)
                                .frame(minHeight: Layout.minTouchTarget)
                                .background(Palette.chipBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Trending topic \(topic)")
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.l)
    }

    @ViewBuilder
    private var feedContent: some View {
        switch viewModel.feed {
        case .idle, .loading:
            LoadingListView()
        case .empty:
            StateMessageView(title: "No articles yet", message: "There’s nothing in this category right now. Pull to refresh or try another category.",
                             systemImage: "tray", actionTitle: "Refresh") { Task { await viewModel.load() } }
                .accessibilityIdentifier("discover.empty")
        case let .failed(error):
            StateMessageView(title: error.title, message: error.message, systemImage: error.systemImage,
                             actionTitle: error.actionTitle) { Task { await viewModel.load() } }
                .accessibilityIdentifier("discover.error")
        case let .loaded(items):
            Text(viewModel.selectedCategoryID.flatMap(ArticleFormatting.categoryTitle) ?? "Latest for you")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Spacing.l)
            ArticleCardList(items: items) { id in
                Task { await viewModel.loadMoreIfNeeded(after: id) }
            }
            .accessibilityIdentifier("discover.feed")
            if viewModel.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading more")
            } else if let error = viewModel.loadMoreError {
                Button("Couldn’t load more — \(error.actionTitle ?? "Retry")") { Task { await viewModel.retryLoadMore() } }
                    .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
            }
        }
    }
}

struct SampleDataBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "testtube.2").foregroundStyle(Palette.sample)
            Text("Showing bundled **sample data**, not live news. Configure a backend to load real content.")
                .font(.footnote)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sample.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sample.banner")
    }
}

struct DailyBriefingCard: View {
    let briefing: DailyBriefing
    let articles: [Article]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Label("Daily Briefing", systemImage: "sun.max").font(.headline)
                Spacer()
                Text(briefing.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if briefing.isAIGenerated { GeneratedContentBadge() }
            Text(briefing.introduction).font(.subheadline)
            ForEach(articles.prefix(3)) { article in
                Label(article.title, systemImage: "circle.fill")
                    .labelStyle(BulletLabelStyle())
                    .font(.subheadline)
                    .lineLimit(2)
            }
            if !briefing.keyThemes.isEmpty {
                Text("Key themes: " + briefing.keyThemes.prefix(4).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full daily briefing")
        .accessibilityIdentifier("briefing.card")
    }
}

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}
