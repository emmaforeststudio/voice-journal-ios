import SwiftData
import SwiftUI

@main
struct VoiceJournalApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: JournalEntry.self)
    }
}
