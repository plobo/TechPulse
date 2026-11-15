import SwiftUI

struct AIReaderView: View {
    private let dependencies: AppDependencies
    @Environment(LibraryStore.self) private var library

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    var body: some View {
        AIReaderContent(dependencies: dependencies, library: library)
    }
}

private struct AIReaderContent: View {
    let dependencies: AppDependencies
    let library: LibraryStore
    @State private var viewModel: AIReaderViewModel
    @State private var showsExplainer = false
    @State private var selected: AIArtifact?
    @State private var confirmClear = false

    init(dependencies: AppDependencies, library: LibraryStore) {
        self.dependencies = dependencies
        self.library = library
        _viewModel = State(initialValue: AIReaderViewModel(dependencies: dependencies, library: library))
    }

    var body: some View {
        Group {
            if viewModel.isEnabled {
                activityList
            } else {
                unavailable
            }
        }
        .background(Palette.screenBackground)
        .navigationTitle("AI Reader")
        .onAppear { Task { await viewModel.load() } }
        .onChange(of: library.preferences) { Task { await viewModel.load() } }
        .sheet(isPresented: $showsExplainer) {
            CodeExplainerSheet(article: nil, dependencies: dependencies, library: library)
                .onDisappear { Task { await viewModel.load() } }
        }
        .sheet(item: $selected) { AIArtifactDetailSheet(artifact: $0, isSampleData: dependencies.isSampleData) }
        .confirmationDialog("Clear all AI history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear AI History", role: .destructive) { Task { await viewModel.clearAll() } }
        }
    }

    private var activityList: some View {
        List {
            if viewModel.isDemo {
                Section { DemoAIBadge() }
            }
            Section("Tools") {
                Button { showsExplainer = true } label: { Label("Explain code", systemImage: "curlybraces") }
            }
            Section {
                if viewModel.items.isEmpty {
                    Text("Summaries, questions, code explanations and diagrams you create will appear here.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(viewModel.items) { item in
                    row(item)
                        .swipeActions { Button("Delete", role: .destructive) { Task { await viewModel.delete(item) } } }
                }
            } header: {
                Text("Recent")
            } footer: {
                Text("Stored only on this device. Notes and reading history are never sent to the AI.")
            }
        }
        .accessibilityIdentifier("aiReader.list")
        .toolbar {
            if !viewModel.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { confirmClear = true }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: AIActivityItem) -> some View {
        switch item {
        case let .artifact(artifact):
            if artifact.kind == .codeExplanation || artifact.articleID == nil {
                Button { selected = artifact } label: { rowLabel(artifact.kind.title, subtitle: artifact.code?.language ?? "", date: item.date, icon: "curlybraces") }
                    .buttonStyle(.plain)
            } else if let articleID = artifact.articleID {
                NavigationLink(value: AppDestination.article(articleID)) {
                    rowLabel(artifact.kind.title + (artifact.summaryType.map { " · \($0.title)" } ?? ""),
                             subtitle: artifact.articleTitle ?? "", date: item.date,
                             icon: artifact.kind == .diagram ? "point.3.connected.trianglepath.dotted" : "text.alignleft")
                }
            }
        case let .conversation(conversation):
            if let articleID = conversation.articleID {
                NavigationLink(value: AppDestination.article(articleID)) {
                    rowLabel("Conversation · \(conversation.messages.count / 2) question\(conversation.messages.count / 2 == 1 ? "" : "s")",
                             subtitle: conversation.articleTitle ?? "", date: item.date, icon: "bubble.left.and.text.bubble.right")
                }
            }
        }
    }

    private func rowLabel(_ title: String, subtitle: String, date: Date, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold))
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(Palette.generatedContent)
        }
        .accessibilityElement(children: .combine)
    }

    private var unavailable: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Group {
                    if viewModel.availability == .available {
                        StateMessageView(title: "Turn on AI features",
                                         message: "Enable AI features in Profile to get on-device summaries, article Q&A, code explanations and diagrams.",
                                         systemImage: "brain")
                    } else {
                        StateMessageView(title: "AI isn’t available on this device",
                                         message: (viewModel.availability ?? .unsupportedOS).message
                                             + " Reading, search, bookmarks and notes all work without AI.",
                                         systemImage: "brain")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("aiReader.unavailable")
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("How AI works here").font(.headline).accessibilityAddTraits(.isHeader)
                    principle("cpu", "Runs on Apple’s on-device model. Article text never leaves your phone.")
                    principle("wand.and.stars", "Every generated summary or answer is labelled “AI-generated”.")
                    principle("doc.text.magnifyingglass", "It only reads what the publisher allows, and says when it saw just an excerpt.")
                    principle("lock.shield", "Your notes and reading history are never sent to the AI.")
                }
                .cardStyle()
            }
            .padding(Spacing.l)
            .frame(maxWidth: Layout.readableWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func principle(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.subheadline) } icon: { Image(systemName: icon).foregroundStyle(Palette.accent) }
    }
}

/// Read-only view of a saved code explanation (or other article-less artifact).
struct AIArtifactDetailSheet: View {
    let artifact: AIArtifact
    var isSampleData = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section { AILabelsRow(provider: artifact.provider, basis: artifact.basis) }
                if let code = artifact.code {
                    Section("Explanation") {
                        LabeledContent("Language", value: code.language)
                        Text(code.explanation).textSelection(.enabled)
                        ForEach(code.risks, id: \.self) { Text("• \($0)") }
                        Label(CodeExplanation.caveat, systemImage: "exclamationmark.shield").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let text = artifact.text { Section { Text(text).textSelection(.enabled) } }
                Section { ShareLink(item: AIReport.text(for: artifact)) { Label("Report a Problem", systemImage: "exclamationmark.bubble") } }
            }
            .navigationTitle(artifact.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
