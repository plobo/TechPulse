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
    private var running: Task<Void, Never>?
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
    var isSampleData: Bool { runtime.dependencies.isSampleData }

    func cancel() {
        running?.cancel()
    }

    /// Only question/answer pairs written by `provider` are sent back as context,
    /// so e.g. Demo AI turns never reach the real model.
    static func history(_ messages: [AIMessage], for provider: AIProviderInfo) -> [AIMessage] {
        var kept: [AIMessage] = []
        var index = 0
        while index < messages.count {
            if messages[index].role == .user, index + 1 < messages.count, messages[index + 1].role == .assistant {
                if messages[index + 1].provider == provider { kept += [messages[index], messages[index + 1]] }
                index += 2
            } else {
                index += 1
            }
        }
        return kept
    }

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
        let task = Task { await self.perform(question) }
        running = task
        await task.value
        isAnswering = false
    }

    private func perform(_ question: String) async {
        let now = runtime.dependencies.dateProvider.now
        let service = runtime.service
        let providerInfo = service.providerInfo
        let history = Self.history(conversation.messages, for: providerInfo)
        let input = input
        let reduced = AIArticleInput.reduced(from: article)
        do {
            let answer = try await runtime.run(key: "\(article.id)|question") {
                do {
                    return try await service.answer(question, input: input, history: history)
                } catch AIServiceError.contextTooLarge {
                    return try await service.answer(question, input: reduced, history: Array(history.suffix(2)))
                }
            }
            conversation.messages.append(AIMessage(id: UUID(), role: .user, content: question, timestamp: now))
            conversation.messages.append(AIMessage(id: UUID(), role: .assistant, content: answer,
                                                   timestamp: runtime.dependencies.dateProvider.now, provider: providerInfo))
            conversation.updatedAt = runtime.dependencies.dateProvider.now
            draft = ""
            try await runtime.dependencies.aiLibrary.saveConversation(conversation)
        } catch is CancellationError {
        } catch {
            self.error = AIRuntime.message(for: error)
        }
    }
}
