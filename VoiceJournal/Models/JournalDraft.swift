import Foundation

struct JournalDraft: Identifiable {
    let id = UUID()
    var title: String
    var body: String
    var journalDate: Date
    var emoji: String
    var language: JournalLanguage
}
