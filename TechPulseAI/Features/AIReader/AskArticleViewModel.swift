import Foundation
import Observation

@MainActor
@Observable
final class AskArticleViewModel {
    let article: Article
    let input: AIArticleInput
    var draft = ""
    private(set) var conversation: AIConversation
    private(set) var isAnswering = false
    private(set) var availability: AIAvailability?
    var error: String?
    private let runtime: AIRuntime

    init(article: Article, dependencies: AppDependencies, library: LibraryStore) {
        self.article = article
        self.input = AIArticleInput.make(from: article)
        self.runtime = AIRuntime(dependencies: dependencies, library: library)
        self.conversation = AIConversation(id: UUID(), articleID: article.id, articleTitle: article.title,
                                           basis: input.basis, messages: [], updatedAt: dependencies.dateProvider.now)
    }

    var isEnabled: Bool { runtime.userEnabled && availability == .available }
    var isDemo: Bool { runtime.demoActive }
    var provider: AIProviderInfo { runtime.service.providerInfo }

    func load() async {
        availability = await runtime.service.availability()
        if let saved = try? await runtime.dependencies.aiLibrary.conversation(articleID: article.id) {
            conversation = saved
        }
    }

    func send() async {
        guard isEnabled, !isAnswering else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try AIPrompts.question(question, input: input, history: [])
        } catch {
            self.error = AIRuntime.message(for: error)
            return
        }
        error = nil
        isAnswering = true
        defer { isAnswering = false }
        let now = runtime.dependencies.dateProvider.now
        let history = conversation.messages
        let service = runtime.service
        let input = input
        do {
            let answer = try await runtime.run(key: "\(article.id)|question") {
                try await service.answer(question, input: input, history: history)
            }
            conversation.messages.append(AIMessage(id: UUID(), role: .user, content: question, timestamp: now))
            conversation.messages.append(AIMessage(id: UUID(), role: .assistant, content: answer,
                                                   timestamp: runtime.dependencies.dateProvider.now))
            conversation.updatedAt = runtime.dependencies.dateProvider.now
            draft = ""
            try await runtime.dependencies.aiLibrary.saveConversation(conversation)
        } catch is CancellationError {
        } catch {
            self.error = AIRuntime.message(for: error)
        }
    }
}
