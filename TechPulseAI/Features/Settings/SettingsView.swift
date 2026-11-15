import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    var body: some View {
        SettingsForm(viewModel: SettingsViewModel(library: library, clearNetworkCache: dependencies.clearNetworkCache,
                                                  aiServices: dependencies.ai, aiLibrary: dependencies.aiLibrary),
                     isSampleData: dependencies.isSampleData)
    }
}

private struct SettingsForm: View {
    @State var viewModel: SettingsViewModel
    let isSampleData: Bool
    @State private var newTechnology = ""
    @State private var exportURL: URL?
    @State private var confirmDeleteAll = false

    private var prefs: UserPreferences { viewModel.preferences }

    var body: some View {
        Form {
            interests
            Section {
                Toggle("Personalize Discover", isOn: binding(prefs.personalizationEnabled) { await viewModel.setPersonalization($0) })
            } footer: {
                Text("Articles matching your interests are shown first with a short explanation. Turn off for a purely chronological feed.")
            }
            Section("Appearance") {
                Picker("Theme", selection: binding(prefs.theme) { await viewModel.setTheme($0) }) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.theme")
            }
            notifications
            ai
            data
            Section("About") {
                NavigationLink("Source & Content Policy", value: AppDestination.sourcePolicy)
                NavigationLink("Privacy", value: AppDestination.privacy)
                NavigationLink("About & Licenses", value: AppDestination.about)
                LabeledContent("Version", value: viewModel.appVersion)
                if isSampleData { LabeledContent("Content", value: "Sample data") }
            }
        }
        .navigationTitle("Profile")
        .confirmationDialog("Delete all on-device data?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    await viewModel.deleteAllData()
                    exportURL = nil
                }
            }
        } message: {
            Text("Bookmarks, notes, history, cached articles and preferences will be permanently removed from this device.")
        }
    }

    private var interests: some View {
        Section {
            ForEach(ArticleCategory.builtIn) { category in
                Toggle(isOn: binding(prefs.selectedCategoryIDs.contains(category.id)) { _ in await viewModel.toggleCategory(category.id) }) {
                    Label(category.title, systemImage: category.iconName)
                }
            }
            ForEach(prefs.followedTechnologies, id: \.self) { tech in
                Text(tech)
                    .swipeActions { Button("Remove", role: .destructive) { Task { await viewModel.removeTechnology(tech) } } }
                    .accessibilityAction(named: "Remove") { Task { await viewModel.removeTechnology(tech) } }
            }
            HStack {
                TextField("Follow a technology (e.g. Swift)", text: $newTechnology)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(addTechnology)
                    .accessibilityIdentifier("settings.newTechnology")
                Button("Add", action: addTechnology).disabled(newTechnology.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Interests")
        } footer: {
            Text("Used only on this device to order your feed.")
        }
    }

    private var notifications: some View {
        Section {
            Toggle("Daily digest", isOn: binding(prefs.notifications.digestEnabled) { await viewModel.setDigestEnabled($0) })
            Toggle("Followed topic alerts", isOn: binding(prefs.notifications.topicAlertsEnabled) { await viewModel.setTopicAlertsEnabled($0) })
            if prefs.notifications.digestEnabled || prefs.notifications.topicAlertsEnabled {
                Picker("Quiet hours start", selection: binding(prefs.notifications.quietHoursStart) {
                    await viewModel.setQuietHours(start: $0, end: prefs.notifications.quietHoursEnd)
                }) { ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) } }
                Picker("Quiet hours end", selection: binding(prefs.notifications.quietHoursEnd) {
                    await viewModel.setQuietHours(start: prefs.notifications.quietHoursStart, end: $0)
                }) { ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) } }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(viewModel.notificationMessage ?? "We’ll only ask for permission when you turn one of these on. Delivery requires the TechPulse backend.")
        }
    }

    private var isAIServiceAvailable: Bool { viewModel.aiAvailability == .available }

    private var ai: some View {
        Section {
            Toggle("AI features", isOn: binding(prefs.aiFeaturesEnabled) { await viewModel.setAIFeatures($0) })
                .disabled(!isAIServiceAvailable)
                .accessibilityIdentifier("settings.aiFeatures")
            Picker("Preferred summary length", selection: binding(prefs.preferredSummaryLength) { await viewModel.setSummaryLength($0) }) {
                ForEach(SummaryLength.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .disabled(!isAIServiceAvailable)
            #if DEBUG
            if viewModel.hasDemoAI {
                Toggle(isOn: binding(prefs.demoAIEnabled) { await viewModel.setDemoAI($0) }) {
                    VStack(alignment: .leading) {
                        Text("Demo AI — fake output")
                        Text("Debug builds only. Uses canned answers instead of the model.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.demoAI")
            }
            #endif
            LabeledContent("Local AI generations", value: "\(prefs.aiGenerationCount)")
        } header: {
            Text("AI & Privacy")
        } footer: {
            Text((viewModel.aiAvailability.map { $0 == .available ? "Runs on Apple’s on-device model; article text never leaves your phone. Your notes and history are never sent." : $0.message }
                  ?? "Checking on-device AI…"))
        }
        .task { await viewModel.loadAIAvailability() }
    }

    private var data: some View {
        Section {
            Button("Export My Data") { Task { exportURL = await viewModel.exportData() } }
            if let exportURL {
                ShareLink(item: exportURL) { Label("Share Export File", systemImage: "square.and.arrow.up") }
            }
            Button("Clear Article Cache") { Task { await viewModel.clearCache() } }
            Button("Clear Reading History") { Task { await viewModel.clearHistory() } }
            Button("Clear AI History") { Task { await viewModel.clearAIHistory() } }
            Button("Delete All Data", role: .destructive) { confirmDeleteAll = true }
                .accessibilityIdentifier("settings.deleteAll")
        } header: {
            Text("Data & Storage")
        } footer: {
            Text(viewModel.storageMessage ?? "All your data is stored on this device. Clearing the cache keeps bookmarked and annotated articles.")
        }
    }

    private func addTechnology() {
        let value = newTechnology
        newTechnology = ""
        Task { await viewModel.addTechnology(value) }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        return Calendar.current.date(from: components)?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }

    /// Bridges a stored preference to a control, persisting changes asynchronously.
    private func binding<T>(_ value: T, set: @escaping @MainActor (T) async -> Void) -> Binding<T> {
        Binding(get: { value }, set: { newValue in Task { await set(newValue) } })
    }
}
