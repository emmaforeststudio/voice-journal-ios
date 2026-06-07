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
}
