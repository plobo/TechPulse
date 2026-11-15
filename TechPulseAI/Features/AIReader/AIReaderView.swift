import SwiftUI

struct AIReaderView: View {
    private let dependencies: AppDependencies
    @Environment(LibraryStore.self) private var library

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                if false {
                    StateMessageView(title: "No AI conversations yet",
                                     message: "Open an article and choose Ask AI to start. Answers use only the article’s permitted content.",
                                     systemImage: "bubble.left.and.text.bubble.right")
                } else {
                    StateMessageView(title: "AI Reader is coming soon",
                                     message: "Summaries at three lengths, article Q&A, code explanations and architecture diagrams are planned for a later release. Reading, search, bookmarks and notes all work without AI.",
                                     systemImage: "brain")
                        .accessibilityIdentifier("aiReader.unavailable")
                }
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("How AI will work here").font(.headline).accessibilityAddTraits(.isHeader)
                    principle("wand.and.stars", "Every generated summary or answer is labelled “AI-generated”.")
                    principle("link", "Answers cite the source article and say when the article doesn’t support an answer.")
                    principle("lock.shield", "Your notes and reading history are never sent to an AI provider.")
                    principle("key", "Provider credentials stay on the TechPulse server, never in the app.")
                }
                .cardStyle()
            }
            .padding(Spacing.l)
            .frame(maxWidth: Layout.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.screenBackground)
        .navigationTitle("AI Reader")
    }

    private func principle(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.subheadline) } icon: { Image(systemName: icon).foregroundStyle(Palette.accent) }
    }
}
