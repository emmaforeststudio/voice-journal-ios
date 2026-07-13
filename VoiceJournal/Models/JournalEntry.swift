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

@Model
final class FutureLetter {
    var id: UUID
    var title: String
    var body: String
    var deliveryDate: Date
    var deliveryMethodRawValue: String
    var notificationIdentifier: String?
    var createdAt: Date
    var updatedAt: Date

    var deliveryMethod: FutureLetterDeliveryMethod {
        get { FutureLetterDeliveryMethod(rawValue: deliveryMethodRawValue) ?? .inAppNotification }
        set { deliveryMethodRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        deliveryDate: Date,
        deliveryMethod: FutureLetterDeliveryMethod,
        notificationIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.deliveryDate = deliveryDate
        self.deliveryMethodRawValue = deliveryMethod.rawValue
        self.notificationIdentifier = notificationIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum FutureLetterDeliveryMethod: String, CaseIterable, Identifiable, Codable {
    case inAppNotification
    case email

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inAppNotification:
            "In-App Notification"
        case .email:
            "Email"
        }
    }
}

enum JournalLanguage: String, CaseIterable, Codable, Identifiable {
    case english
    case chinese
    case korean
    case japanese
    case german
    case french
    case spanish
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            "English"
        case .chinese:
            "Chinese"
        case .korean:
            "Korean"
        case .japanese:
            "Japanese"
        case .german:
            "German"
        case .french:
            "French"
        case .spanish:
            "Spanish"
        case .other:
            "Other Language"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english:
            "en-US"
        case .chinese:
            "zh-Hans"
        case .korean:
            "ko-KR"
        case .japanese:
            "ja-JP"
        case .german:
            "de-DE"
        case .french:
            "fr-FR"
        case .spanish:
            "es-ES"
        case .other:
            "en-US"
        }
    }
}
