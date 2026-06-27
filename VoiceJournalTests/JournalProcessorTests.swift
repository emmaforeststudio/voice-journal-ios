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

    func testMarkdownExportIncludesJournalMetadataAndBody() {
        let entry = JournalEntry(
            title: "A Quiet Morning",
            body: "I woke up calmer today.\n\nThe walk helped.",
            journalDate: date(year: 2026, month: 6, day: 7),
            emoji: "😊",
            language: .english
        )

        let markdown = MarkdownJournalExporter.makeMarkdown(entries: [entry])

        XCTAssertTrue(markdown.contains("# Voice Journal Export"))
        XCTAssertTrue(markdown.contains("## A Quiet Morning"))
        XCTAssertTrue(markdown.contains("- Mood: 😊"))
        XCTAssertTrue(markdown.contains("- Language: English"))
        XCTAssertTrue(markdown.contains("I woke up calmer today.\n\nThe walk helped."))
    }

    func testMarkdownExportEmptyState() {
        XCTAssertEqual(MarkdownJournalExporter.makeMarkdown(entries: []), "# Voice Journal Export\n\nNo journals yet.")
    }

    func testMarkdownImportReadsExportedJournal() {
        let entry = JournalEntry(
            title: "A Quiet Morning",
            body: "I woke up calmer today.\n\nThe walk helped.",
            journalDate: date(year: 2026, month: 6, day: 7),
            emoji: "😊",
            language: .english
        )
        let markdown = MarkdownJournalExporter.makeMarkdown(entries: [entry])

        let imported = MarkdownJournalImporter.importEntries(from: markdown, fallbackTitle: "Backup")

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].title, "A Quiet Morning")
        XCTAssertEqual(imported[0].body, "I woke up calmer today.\n\nThe walk helped.")
        XCTAssertEqual(imported[0].emoji, "😊")
        XCTAssertEqual(imported[0].language, .english)
    }

    func testMarkdownImportFallsBackToPlainTextJournal() {
        let imported = MarkdownJournalImporter.importEntries(
            from: "This came from another journal app.",
            fallbackTitle: "Old Journal"
        )

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].title, "Old Journal")
        XCTAssertEqual(imported[0].body, "This came from another journal app.")
        XCTAssertEqual(imported[0].language, .other)
    }

    func testInsightStreakCountsUniqueJournalDays() {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = date(year: 2026, month: 6, day: 11)
        let entries = [
            JournalEntry(title: "One", body: "First", journalDate: date(year: 2026, month: 6, day: 11), emoji: "😊", language: .english),
            JournalEntry(title: "Two", body: "Second same day", journalDate: date(year: 2026, month: 6, day: 11, hour: 18), emoji: "😔", language: .english),
            JournalEntry(title: "Three", body: "Yesterday", journalDate: date(year: 2026, month: 6, day: 10), emoji: "😊", language: .english),
            JournalEntry(title: "Four", body: "Gap before this", journalDate: date(year: 2026, month: 6, day: 8), emoji: "😊", language: .english)
        ]

        XCTAssertEqual(JournalInsightCalculator.currentStreak(entries, referenceDate: referenceDate, calendar: calendar), 2)
        XCTAssertEqual(JournalInsightCalculator.longestStreak(entries, calendar: calendar), 2)
    }

    func testInsightMoodCountsAndAverageLength() {
        let entries = [
            JournalEntry(title: "A", body: "A short English journal.", journalDate: .now, emoji: "😊", language: .english),
            JournalEntry(title: "B", body: "今天我很开心", journalDate: .now, emoji: "😊", language: .chinese),
            JournalEntry(title: "C", body: "I felt tired.", journalDate: .now, emoji: "😴", language: .english)
        ]

        let moodCounts = JournalInsightCalculator.moodCounts(entries)

        XCTAssertEqual(moodCounts.first?.emoji, "😊")
        XCTAssertEqual(moodCounts.first?.count, 2)
        XCTAssertGreaterThan(JournalInsightCalculator.averageLength(entries), 0)
    }

    func testInsightThemesPreferRepeatedMeaningfulConcepts() {
        let entries = [
            JournalEntry(title: "Project Focus", body: "The project planning session helped the project feel clearer.", journalDate: .now, emoji: "😊", language: .english),
            JournalEntry(title: "Family Dinner", body: "Family dinner felt warm, and family time helped me relax.", journalDate: .now, emoji: "🥰", language: .english),
            JournalEntry(title: "Project Notes", body: "I came back to the project and wrote a clearer plan.", journalDate: .now, emoji: "✨", language: .english)
        ]

        let themes = JournalInsightCalculator.topThemes(entries, limit: 3)

        XCTAssertEqual(themes.first, "Work Stress")
        XCTAssertTrue(themes.contains("Family Time"))
    }

    func testInsightThemeCloudDetectsSpecificJournalThemes() {
        let entries = [
            JournalEntry(title: "Awkward Call", body: "The long call was awkward and uncomfortable.", journalDate: .now, emoji: "😤", language: .english),
            JournalEntry(title: "Sleep", body: "I couldn't sleep and woke up exhausted.", journalDate: .now, emoji: "😴", language: .english),
            JournalEntry(title: "Acting", body: "Acting practice and rehearsal helped my monologue.", journalDate: .now, emoji: "✨", language: .english)
        ]

        let themes = JournalInsightCalculator.themeCloud(entries, limit: 6).map(\.theme)

        XCTAssertTrue(themes.contains("Long Calls"))
        XCTAssertTrue(themes.contains("Awkwardness"))
        XCTAssertTrue(themes.contains("Sleep Struggles"))
        XCTAssertTrue(themes.contains("Acting Practice"))
    }

    func testInsightThemeCloudDoesNotPromoteFillerWords() {
        let entries = [
            JournalEntry(
                title: "Messy Test",
                body: "It's working very much, but 这个 没有 should not become a theme. I felt disappointed that the recording test did not work.",
                journalDate: .now,
                emoji: "😔",
                language: .english
            )
        ]

        let themes = JournalInsightCalculator.themeCloud(entries, limit: 8).map(\.theme)

        XCTAssertTrue(themes.contains("Dissatisfaction"))
        XCTAssertTrue(themes.contains("App Testing"))
        XCTAssertFalse(themes.contains("It's"))
        XCTAssertFalse(themes.contains("这个"))
        XCTAssertFalse(themes.contains("没有"))
        XCTAssertFalse(themes.contains("Very"))
        XCTAssertFalse(themes.contains("It's Working"))
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
