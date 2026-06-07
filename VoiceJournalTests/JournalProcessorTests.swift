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

    func testTitleUsesFirstEnglishSentence() {
        let processor = JournalProcessor()

        let title = processor.makeTitle(from: "I felt proud after finishing the project today. Then I rested.", language: .english)

        XCTAssertEqual(title, "I felt proud after finishing the project today")
    }
}
