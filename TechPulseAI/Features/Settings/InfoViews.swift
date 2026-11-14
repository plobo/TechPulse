import SwiftUI

struct PrivacyView: View {
    var body: some View {
        List {
            Section("What stays on your device") {
                Text("Bookmarks, notes, reading history, preferences and cached article metadata are stored locally with SwiftData. You can export or delete them in Profile → Data & Storage.")
            }
            Section("What is sent to the network") {
                Text("Feed, search and briefing requests go to the TechPulse content service. Search queries are sent to perform the search. In sample-data mode nothing is sent.")
            }
            Section("AI processing") {
                Text("AI features are off and unavailable in this version. When introduced, article text will be processed only when you ask, via the TechPulse backend; notes and history will never be sent without your explicit action.")
            }
            Section("Analytics") {
                Text("This version collects no analytics and does not log your searches, questions or notes.")
            }
        }
        .navigationTitle("Privacy")
    }
}

struct SourcePolicyView: View {
    let dependencies: AppDependencies
    @State private var sources: [Source] = []

    var body: some View {
        List {
            Section("Publisher content") {
                Text("TechPulse AI shows titles, summaries and short excerpts provided through approved feeds and APIs, always with the publisher’s name and a link to the original. Full text appears only where the publisher’s terms allow it.")
                Text("We respect publisher terms, robots policies, API terms and rate limits. Sources are ingested by the TechPulse backend; the app never scrapes websites.")
            }
            if dependencies.isSampleData {
                Section("Sample data") {
                    Text("This build is showing bundled sample content written for demonstration. It is not real news, and every link points to example.com.")
                }
            }
            Section("Sources") {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(source.name).font(.headline)
                        if let attribution = source.attribution { Text(attribution).font(.caption).foregroundStyle(.secondary) }
                        Link(source.homepageURL.host() ?? source.homepageURL.absoluteString, destination: source.homepageURL)
                            .font(.caption)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Source Policy")
        .task { sources = (try? await dependencies.catalog.sources()) ?? [] }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                Text("TechPulse AI helps developers move from discovery to understanding: Discover → Understand → Visualize → Implement → Learn.")
            }
            Section("Licenses") {
                Text("Built with Apple frameworks (SwiftUI, SwiftData, Foundation). No third-party libraries are bundled in this version.")
            }
            Section("Generated content") {
                Text("Anything produced by AI is labelled “AI-generated”. AI-generated code is not guaranteed to be secure or production-ready.")
            }
        }
        .navigationTitle("About")
    }
}
