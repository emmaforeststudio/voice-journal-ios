import Foundation
import SwiftData

@Model
final class JournalEntry {
    var id: UUID
    var title: String
    var body: String
    var journalDate: Date
    var emoji: String
    var languageRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var language: JournalLanguage {
        get { JournalLanguage(rawValue: languageRawValue) ?? .english }
        set { languageRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        journalDate: Date,
        emoji: String,
        language: JournalLanguage,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.journalDate = journalDate
        self.emoji = emoji
        self.languageRawValue = language.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum JournalLanguage: String, CaseIterable, Codable, Identifiable {
    case english
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            "English"
        case .chinese:
            "Chinese"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english:
            "en-US"
        case .chinese:
            "zh-Hans"
        }
    }
}
