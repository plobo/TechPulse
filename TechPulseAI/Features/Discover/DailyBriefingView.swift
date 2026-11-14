import SwiftUI

@MainActor
@Observable
final class DailyBriefingViewModel {
    private(set) var state: LoadState<(briefing: DailyBriefing, articles: [Article])> = .idle
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func load() async {
        state = .loading
        do {
            let briefing = try await dependencies.briefing.dailyBriefing()
            var articles: [Article] = []
            for id in briefing.articleIDs {
                if let article = try? await dependencies.articles.article(id: id) { articles.append(article) }
            }
            state = articles.isEmpty ? .empty : .loaded((briefing, articles))
        } catch is CancellationError {
        } catch {
            state = .failed(UserFacingError(error))
        }
    }
}

struct DailyBriefingView: View {
    @State private var viewModel: DailyBriefingViewModel

    init(dependencies: AppDependencies) {
        _viewModel = State(initialValue: DailyBriefingViewModel(dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .idle, .loading:
                LoadingListView()
            case .empty:
                StateMessageView(title: "Nothing new today", message: "There are no recent highlights yet.", systemImage: "sun.haze")
            case let .failed(error):
                StateMessageView(title: error.title, message: error.message, systemImage: error.systemImage,
                                 actionTitle: error.actionTitle) { Task { await viewModel.load() } }
            case let .loaded(value):
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(value.briefing.date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                        if value.briefing.isAIGenerated { GeneratedContentBadge() }
                        Text(value.briefing.introduction).font(.title3)
                        if !value.briefing.keyThemes.isEmpty {
                            Text("Key themes: " + value.briefing.keyThemes.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    ArticleCardList(items: value.articles.map { FeedItem(article: $0, reason: nil) })
                }
                .padding(.vertical, Spacing.m)
                .frame(maxWidth: Layout.readableWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.screenBackground)
        .navigationTitle("Daily Briefing")
        .refreshable { await viewModel.load() }
        .task { if viewModel.state.value == nil { await viewModel.load() } }
    }
}
