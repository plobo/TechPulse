import Foundation
import Observation

@MainActor
@Observable
final class AIReaderViewModel {
    private(set) var items: [AIActivityItem] = []
    private(set) var availability: AIAvailability?
    private let runtime: AIRuntime

    init(dependencies: AppDependencies, library: LibraryStore) {
        self.runtime = AIRuntime(dependencies: dependencies, library: library)
    }

    var isEnabled: Bool { runtime.userEnabled && availability == .available }
    var isDemo: Bool { runtime.demoActive }

    func load() async {
        availability = await runtime.service.availability()
        items = (try? await runtime.dependencies.aiLibrary.recentAIActivity(limit: 100)) ?? []
    }

    func delete(_ item: AIActivityItem) async {
        do {
            try await runtime.dependencies.aiLibrary.deleteAIItem(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            runtime.library.lastErrorMessage = "Couldn’t delete this item."
        }
    }

    func clearAll() async {
        do {
            try await runtime.dependencies.aiLibrary.clearAIHistory()
            items = []
        } catch {
            runtime.library.lastErrorMessage = "Couldn’t clear AI history."
        }
    }
}
