import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordJournalView {
                selectedTab = 1
            }
                .tabItem {
                    Label("Create", systemImage: "plus.circle.fill")
                }
                .tag(0)

            CalendarJournalView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(1)

            InsightsJournalView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.fill")
                }
                .tag(2)
        }
    }
}
