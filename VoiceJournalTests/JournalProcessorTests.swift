import XCTest
@testable import VoiceJournal

final class JournalProcessorTests: XCTestCase {
    func testEnglishCleanupRemovesFillersAndCapitalizes() {
        let processor = JournalProcessor()

        let result = processor.clean("um today was was kind of hard. i felt better after a walk.", language: .english)

        XCTAssertEqual(result, "Today was hard. I felt better after a walk.")
    }

    func testChineseCleanupRemovesCommonFillers() {
        let processor = JournalProcessor()

        let result = processor.clean("嗯今天就是有点累，但是然后然后我还是完成了工作。", language: .chinese)

        XCTAssertEqual(result, "今天有点累，但是我还是完成了工作。")
    }

    func testCleanupPreservesMeaningfulParagraphBreaks() {
        let processor = JournalProcessor()

        let result = processor.clean(
            "Today was difficult.   I felt frustrated.\n\n\nLater, a walk helped me feel better.",
            language: .english
        )

        XCTAssertEqual(
            result,
            "Today was difficult. I felt frustrated.\n\nLater, a walk helped me feel better."
        )
    }

    func testTitleTurnsVoiceJournalTestIntoShortTitle() {
        let processor = JournalProcessor()

        let title = processor.makeTitle(
            from: "Hey I wanted to test this voice journal app hopefully it's good",
            language: .english
        )

        XCTAssertEqual(title, "Testing Voice Journal")
    }

    func testTitleRecognizesAccomplishment() {
        let processor = JournalProcessor()

        let title = processor.makeTitle(from: "I finished a difficult project today.", language: .english)

        XCTAssertEqual(title, "A Small Win")
    }

    func testMoodEmojiRecognizesHopefulJournal() {
        let processor = JournalProcessor()

        let emoji = processor.moodEmoji(
            from: "I wanted to test this voice journal app. Hopefully it's good.",
            language: .english
        )

        XCTAssertEqual(emoji, "😊")
    }

    func testMoodEmojiRecognizesTiredChineseJournal() {
        let processor = JournalProcessor()

        let emoji = processor.moodEmoji(from: "今天工作以后有点累。", language: .chinese)

        XCTAssertEqual(emoji, "😴")
    }

    func testDailyMoodBalancesMostlyHappyEntries() {
        let processor = JournalProcessor()

        let emoji = processor.dailyMoodEmoji(from: ["😊", "😊", "😊", "😊", "😊", "😔"])

        XCTAssertEqual(emoji, "🙂")
    }

    func testDailyMoodShowsStrongHappinessWhenConsistent() {
        let processor = JournalProcessor()

        let emoji = processor.dailyMoodEmoji(from: ["😊", "🥰", "✨"])

        XCTAssertEqual(emoji, "😊")
    }

    func testUnsupportedOpenAIEmojiFallsBackToDetectedMood() {
        let processor = JournalProcessor()

        let emoji = processor.normalizedMoodEmoji("😞", body: "I feel disappointed and sad.", language: .english)

        XCTAssertEqual(emoji, "😔")
    }

    func testFrenchFallbackPreservesOriginalText() {
        let processor = JournalProcessor()
        let french = "Aujourd'hui, je suis heureuse."

        XCTAssertEqual(processor.clean(french, language: .french), french)
        XCTAssertEqual(processor.makeTitle(from: french, language: .french), "Aujourd'hui, je suis heureuse")
    }

    func testRequestedLanguagesHaveExpectedLocales() {
        XCTAssertEqual(JournalLanguage.english.localeIdentifier, "en-US")
        XCTAssertEqual(JournalLanguage.chinese.localeIdentifier, "zh-Hans")
        XCTAssertEqual(JournalLanguage.korean.localeIdentifier, "ko-KR")
        XCTAssertEqual(JournalLanguage.japanese.localeIdentifier, "ja-JP")
        XCTAssertEqual(JournalLanguage.german.localeIdentifier, "de-DE")
        XCTAssertEqual(JournalLanguage.french.localeIdentifier, "fr-FR")
        XCTAssertEqual(JournalLanguage.spanish.localeIdentifier, "es-ES")
    }
}
