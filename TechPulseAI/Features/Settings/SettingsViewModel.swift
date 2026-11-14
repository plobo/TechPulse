import Foundation
import Observation
import UserNotifications

protocol NotificationAuthorizing: Sendable {
    func requestAuthorization() async -> Bool
}

struct SystemNotificationAuthorizer: NotificationAuthorizing {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    let library: LibraryStore
    private let notifications: any NotificationAuthorizing
    var notificationMessage: String?
    var storageMessage: String?

    init(library: LibraryStore, notifications: any NotificationAuthorizing = SystemNotificationAuthorizer()) {
        self.library = library
        self.notifications = notifications
    }

    var preferences: UserPreferences { library.preferences }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    func toggleCategory(_ id: CategoryID) async {
        await library.updatePreferences { prefs in
            if let index = prefs.selectedCategoryIDs.firstIndex(of: id) {
                prefs.selectedCategoryIDs.remove(at: index)
            } else {
                prefs.selectedCategoryIDs.append(id)
            }
        }
    }

    func addTechnology(_ raw: String) async {
        let tech = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tech.isEmpty, tech.count <= 40,
              !preferences.followedTechnologies.contains(where: { $0.caseInsensitiveCompare(tech) == .orderedSame }) else { return }
        await library.updatePreferences { $0.followedTechnologies.append(tech) }
    }

    func removeTechnology(_ tech: String) async {
        await library.updatePreferences { $0.followedTechnologies.removeAll { $0 == tech } }
    }

    func setTheme(_ theme: AppTheme) async {
        await library.updatePreferences { $0.theme = theme }
    }

    func setPersonalization(_ enabled: Bool) async {
        await library.updatePreferences { $0.personalizationEnabled = enabled }
    }

    func setAIFeatures(_ enabled: Bool) async {
        await library.updatePreferences { $0.aiFeaturesEnabled = enabled }
    }

    func setSummaryLength(_ length: SummaryLength) async {
        await library.updatePreferences { $0.preferredSummaryLength = length }
    }

    /// Asks for notification permission only when the user turns a notification on.
    func setDigestEnabled(_ enabled: Bool) async {
        await setNotification(enabled) { $0.digestEnabled = $1 }
    }

    func setTopicAlertsEnabled(_ enabled: Bool) async {
        await setNotification(enabled) { $0.topicAlertsEnabled = $1 }
    }

    func setQuietHours(start: Int, end: Int) async {
        await library.updatePreferences {
            $0.notifications.quietHoursStart = start
            $0.notifications.quietHoursEnd = end
        }
    }

    private func setNotification(_ enabled: Bool, apply: @escaping (inout NotificationSettings, Bool) -> Void) async {
        if enabled {
            guard await notifications.requestAuthorization() else {
                notificationMessage = "Notifications are turned off for TechPulse AI. You can enable them in the Settings app."
                return
            }
        }
        notificationMessage = nil
        await library.updatePreferences { apply(&$0.notifications, enabled) }
    }

    func exportData() async -> URL? {
        do {
            let data = try await library.repository.exportData()
            let stamp = Date().formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("TechPulse-Export-\(stamp).json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            storageMessage = "Export failed."
            return nil
        }
    }

    func clearCache() async {
        let removed = await library.clearCache()
        storageMessage = removed == 0 ? "Cache is already empty." : "Removed \(removed) cached article\(removed == 1 ? "" : "s")."
    }

    func clearHistory() async {
        await library.clearHistory()
        storageMessage = "Reading history cleared."
    }

    func deleteAllData() async {
        await library.deleteAllData()
        storageMessage = "All on-device data deleted."
    }
}
