import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarJournalView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(0)

            RecordJournalView {
                selectedTab = 0
            }
                .tabItem {
                    Label("Record", systemImage: "mic.circle.fill")
                }
                .tag(1)

            SearchJournalView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(2)
        }
    }
}
