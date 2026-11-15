import SwiftUI

struct CodeExplainerSheet: View {
    @State private var viewModel: CodeExplainerViewModel
    @Environment(\.dismiss) private var dismiss

    init(article: Article?, dependencies: AppDependencies, library: LibraryStore) {
        _viewModel = State(initialValue: CodeExplainerViewModel(article: article, dependencies: dependencies, library: library))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $viewModel.snippet)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 140)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Code to explain")
                        .accessibilityIdentifier("ai.code.field")
                } header: {
                    Text("Paste code")
                } footer: {
                    Text("Up to \(AIPrompts.snippetLimit) characters. Processed on this device.")
                }
                Section {
                    Button {
                        Task { await viewModel.explain() }
                    } label: {
                        if viewModel.result.isLoading { ProgressView() } else { Label("Explain", systemImage: "sparkles") }
                    }
                    .disabled(!viewModel.isEnabled || viewModel.result.isLoading)
                    .accessibilityIdentifier("ai.code.explain")
                }
                result
            }
            .navigationTitle("Explain Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await viewModel.load() }
        }
    }

    @ViewBuilder private var result: some View {
        switch viewModel.result {
        case .idle, .loading:
            EmptyView()
        case let .failed(message):
            Section { Label(message, systemImage: "exclamationmark.triangle") }
        case let .loaded(artifact):
            if let code = artifact.code {
                Section {
                    AILabelsRow(provider: artifact.provider, basis: nil)
                    LabeledContent("Language", value: code.language)
                    Text(code.explanation).textSelection(.enabled)
                    if !code.risks.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Risks & gotchas").font(.subheadline.weight(.semibold))
                            ForEach(code.risks, id: \.self) { Text("• \($0)") }
                        }
                    }
                    Label(CodeExplanation.caveat, systemImage: "exclamationmark.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                    ShareLink(item: AIReport.text(for: artifact)) { Label("Report a Problem", systemImage: "exclamationmark.bubble") }
                } header: {
                    Text("Explanation")
                }
            }
        }
    }
}
