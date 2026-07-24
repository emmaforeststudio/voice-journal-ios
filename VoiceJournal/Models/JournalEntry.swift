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
    var originalTitle: String?
    var originalBody: String?
    var translatedTitle: String?
    var translatedBody: String?
    var translationLanguageRawValue: String?
    var displayedVersionRawValue: String?

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
        originalTitle: String? = nil,
        originalBody: String? = nil,
        translatedTitle: String? = nil,
        translatedBody: String? = nil,
        translationLanguage: TranslationLanguage? = nil,
        displayedVersion: TranslatedContentVersion = .original,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.journalDate = journalDate
        self.emoji = emoji
        self.languageRawValue = language.rawValue
        self.originalTitle = originalTitle
        self.originalBody = originalBody
        self.translatedTitle = translatedTitle
        self.translatedBody = translatedBody
        self.translationLanguageRawValue = translationLanguage?.rawValue
        self.displayedVersionRawValue = displayedVersion.rawValue
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
    var recipientEmail: String?
    var remoteDeliveryStatusRawValue: String?
    var remoteDeliveredAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var originalTitle: String?
    var originalBody: String?
    var translatedTitle: String?
    var translatedBody: String?
    var translationLanguageRawValue: String?
    var selectedVersionRawValue: String?

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
        recipientEmail: String? = nil,
        remoteDeliveryStatus: FutureLetterEmailStatus? = nil,
        remoteDeliveredAt: Date? = nil,
        originalTitle: String? = nil,
        originalBody: String? = nil,
        translatedTitle: String? = nil,
        translatedBody: String? = nil,
        translationLanguage: TranslationLanguage? = nil,
        selectedVersion: TranslatedContentVersion = .original,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.deliveryDate = deliveryDate
        self.deliveryMethodRawValue = deliveryMethod.rawValue
        self.notificationIdentifier = notificationIdentifier
        self.recipientEmail = recipientEmail
        self.remoteDeliveryStatusRawValue = remoteDeliveryStatus?.rawValue
        self.remoteDeliveredAt = remoteDeliveredAt
        self.originalTitle = originalTitle
        self.originalBody = originalBody
        self.translatedTitle = translatedTitle
        self.translatedBody = translatedBody
        self.translationLanguageRawValue = translationLanguage?.rawValue
        self.selectedVersionRawValue = selectedVersion.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum TranscriptOutputMode: String, CaseIterable, Identifiable {
    case asSpoken
    case translate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asSpoken: "Keep As Spoken"
        case .translate: "Translate Multilingual Recordings"
        }
    }

    static func value(for rawValue: String) -> TranscriptOutputMode {
        TranscriptOutputMode(rawValue: rawValue) ?? .asSpoken
    }
}

enum TranslatedContentVersion: String, CaseIterable, Identifiable {
    case original
    case translated

    var id: String { rawValue }
}

enum TranslationLanguage: String, CaseIterable, Identifiable, Codable {
    case english
    case chineseSimplified
    case chineseTraditional
    case cantonese
    case korean
    case japanese
    case spanish
    case french
    case german
    case italian
    case portuguese
    case arabic
    case hindi
    case bengali
    case russian
    case ukrainian
    case polish
    case dutch
    case turkish
    case vietnamese
    case thai
    case indonesian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .chineseSimplified: "Chinese (Simplified)"
        case .chineseTraditional: "Chinese (Traditional)"
        case .cantonese: "Cantonese"
        case .korean: "Korean"
        case .japanese: "Japanese"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .arabic: "Arabic"
        case .hindi: "Hindi"
        case .bengali: "Bengali"
        case .russian: "Russian"
        case .ukrainian: "Ukrainian"
        case .polish: "Polish"
        case .dutch: "Dutch"
        case .turkish: "Turkish"
        case .vietnamese: "Vietnamese"
        case .thai: "Thai"
        case .indonesian: "Indonesian"
        }
    }

    var compactDisplayName: String {
        displayName
            .components(separatedBy: " (")
            .first ?? displayName
    }

    static func value(for rawValue: String?) -> TranslationLanguage {
        guard let rawValue else { return .english }
        return TranslationLanguage(rawValue: rawValue) ?? .english
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
