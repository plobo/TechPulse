import SwiftUI

struct AskArticleSheet: View {
    @State private var viewModel: AskArticleViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(article: Article, dependencies: AppDependencies, library: LibraryStore) {
        _viewModel = State(initialValue: AskArticleViewModel(article: article, dependencies: dependencies, library: library))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spacing.m) {
                            Text("Answers use only this article’s permitted text.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let label = viewModel.input.basis.label {
                                Label(label, systemImage: "doc.text.magnifyingglass").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(viewModel.conversation.messages) { message in
                                bubble(message).id(message.id)
                            }
                            if viewModel.isAnswering {
                                ProgressView("Thinking on device…").font(.footnote)
                            }
                        }
                        .padding(Spacing.l)
                    }
                    .onChange(of: viewModel.conversation.messages.count) {
                        if let last = viewModel.conversation.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                if let error = viewModel.error {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, Spacing.l)
                }
                composer
            }
            .navigationTitle("Ask this article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await viewModel.load() }
        }
    }

    private func bubble(_ message: AIMessage) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if message.role == .assistant {
                AILabelsRow(provider: viewModel.provider, basis: nil)
            }
            Text(message.content).textSelection(.enabled)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? Palette.accent.opacity(0.12) : Palette.cardBackground,
                    in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel((message.role == .user ? "You: " : "AI-generated answer: ") + message.content)
    }

    private var composer: some View {
        HStack(alignment: .bottom) {
            TextField(viewModel.isEnabled ? "Ask about this article" : "AI isn’t available", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .disabled(!viewModel.isEnabled)
                .accessibilityIdentifier("ai.ask.field")
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
                    .frame(minWidth: Layout.minTouchTarget, minHeight: Layout.minTouchTarget)
            }
            .disabled(!viewModel.isEnabled || viewModel.isAnswering || viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send question")
            .accessibilityIdentifier("ai.ask.send")
        }
        .padding(Spacing.m)
        .background(.bar)
    }
}
