import SwiftUI

@main
struct TechPulseAIApp: App {
    private let startup: Result<AppDependencies, any Error>

    init() {
        startup = Result { try AppDependencies.live(configuration: .current) }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case let .success(dependencies):
                RootView(dependencies: dependencies)
            case .failure:
                StateMessageView(title: "TechPulse couldn’t start",
                                 message: "Local storage could not be opened. Restart the app; if this continues, reinstall it.",
                                 systemImage: "externaldrive.badge.exclamationmark")
            }
        }
    }
}
