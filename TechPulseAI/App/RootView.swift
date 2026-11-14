import SwiftUI

struct RootView: View {
    @State private var selectedTab: AppTab = .discover

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Text(tab.title)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
                    .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
    }
}
