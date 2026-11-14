import Foundation
import Testing
@testable import TechPulseAI

@Suite("AppConfiguration")
struct AppConfigurationTests {
    @Test func defaultsToSampleDataWhenNoBaseURLConfigured() {
        let config = AppConfiguration(values: [:])
        #expect(config.dataSource == .sample)
    }

    @Test func usesRemoteDataWhenHTTPSBaseURLConfigured() {
        let config = AppConfiguration(values: ["TECHPULSE_API_BASE_URL": "https://api.example.com"])
        #expect(config.dataSource == .remote(URL(string: "https://api.example.com")!))
    }

    @Test func rejectsNonHTTPSBaseURLAndFallsBackToSample() {
        let config = AppConfiguration(values: ["TECHPULSE_API_BASE_URL": "http://api.example.com"])
        #expect(config.dataSource == .sample)
    }

    @Test func uiTestingFlagSelectsInMemoryStore() {
        let config = AppConfiguration(values: [:], arguments: ["-ui-testing"])
        #expect(config.usesInMemoryStore)
        #expect(!AppConfiguration(values: [:]).usesInMemoryStore)
    }

    @Test func persistentStoreFlagKeepsDiskStoreForRelaunchTests() {
        let config = AppConfiguration(values: [:], arguments: ["-ui-testing", "-persistent-store", "-reset-store"])
        #expect(!config.usesInMemoryStore)
        #expect(config.resetsStoreOnLaunch)
        #expect(!AppConfiguration(values: [:], arguments: ["-reset-store"]).resetsStoreOnLaunch, "reset only allowed under UI testing")
    }
}

@Suite("AppTab")
struct AppTabTests {
    @Test func hasFiveTabsInOrder() {
        #expect(AppTab.allCases == [.discover, .explore, .aiReader, .library, .profile])
    }
}
