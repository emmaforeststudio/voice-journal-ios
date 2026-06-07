import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            CalendarJournalView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            RecordJournalView()
                .tabItem {
                    Label("Record", systemImage: "mic.circle.fill")
                }

            SearchJournalView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
        }
    }
}
