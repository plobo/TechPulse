import SwiftUI

struct RootView: View {
    let dependencies: AppDependencies
    @State private var library: LibraryStore
    @State private var selectedTab: AppTab = .discover
    @State private var paths: [AppTab: [AppDestination]] = [:]

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _library = State(initialValue: LibraryStore(repository: dependencies.library))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                NavigationStack(path: binding(for: tab)) {
                    tabRoot(tab)
                        .navigationDestination(for: AppDestination.self) { destination in
                            AppDestinationView(destination: destination, dependencies: dependencies, library: library)
                        }
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .environment(library)
        .environment(\.dependencies, dependencies)
        .preferredColorScheme(library.preferences.theme.colorScheme)
        .task { await library.load() }
    }

    private func binding(for tab: AppTab) -> Binding<[AppDestination]> {
        Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .discover: DiscoverView(dependencies: dependencies, library: library)
        case .explore: ExploreView(dependencies: dependencies)
        case .aiReader: AIReaderView(dependencies: dependencies)
        case .library: LibraryView(dependencies: dependencies)
        case .profile: SettingsView(dependencies: dependencies)
        }
    }
}

/// Resolves typed navigation destinations for every tab.
struct AppDestinationView: View {
    let destination: AppDestination
    let dependencies: AppDependencies
    let library: LibraryStore

    var body: some View {
        switch destination {
        case let .article(id):
            ArticleDetailView(articleID: id, dependencies: dependencies, library: library)
        case let .category(id):
            ArticleListScreen(kind: .category(id), dependencies: dependencies)
        case let .source(id):
            ArticleListScreen(kind: .source(id), dependencies: dependencies)
        case let .search(query):
            SearchView(dependencies: dependencies, initialQuery: query)
        case .dailyBriefing:
            DailyBriefingView(dependencies: dependencies)
        case .privacy:
            PrivacyView()
        case .sourcePolicy:
            SourcePolicyView(dependencies: dependencies)
        case .about:
            AboutView()
        }
    }
}

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
