import Foundation

struct JournalProcessor {
    func makeDraft(from rawText: String, language: JournalLanguage, date: Date = .now) -> JournalDraft {
        let cleaned = clean(rawText, language: language)
        return JournalDraft(
            title: makeTitle(from: cleaned, language: language),
            body: cleaned,
            journalDate: date,
            emoji: "🙂",
            language: language
        )
    }

    func clean(_ rawText: String, language: JournalLanguage) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        switch language {
        case .english:
            text = cleanEnglish(text)
        case .chinese:
            text = cleanChinese(text)
        }

        return normalizeWhitespace(text)
    }

    func makeTitle(from body: String, language: JournalLanguage) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled Journal" }

        let separators = CharacterSet(charactersIn: ".!?。！？\n")
        let firstSentence = trimmed
            .components(separatedBy: separators)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed

        switch language {
        case .english:
            return firstSentence
                .split(separator: " ")
                .prefix(8)
                .joined(separator: " ")
        case .chinese:
            return String(firstSentence.prefix(14))
        }
    }

    private func cleanEnglish(_ input: String) -> String {
        var text = input
        let fillerPatterns = [
            "\\b(um+|uh+|ah+|er+|hmm+|mm+)\\b[, ]*",
            "\\b(like|you know|i mean|sort of|kind of)\\b[, ]*"
        ]

        for pattern in fillerPatterns {
            text = text.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        text = text.replacingOccurrences(
            of: "\\b(\\w+)\\s+\\1\\b",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "\\s+([,.!?])", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "([.!?])\\s*([A-Za-z])", with: "$1 $2", options: .regularExpression)

        return capitalizeSentences(text)
    }

    private func cleanChinese(_ input: String) -> String {
        var text = input
        let fillers = ["那个", "嗯", "呃", "啊", "就是", "然后然后"]
        for filler in fillers {
            text = text.replacingOccurrences(of: filler, with: "")
        }
        text = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "，，", with: "，")
        text = text.replacingOccurrences(of: "。。", with: "。")
        return text
    }

    private func normalizeWhitespace(_ input: String) -> String {
        input
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeSentences(_ input: String) -> String {
        var result = ""
        var shouldCapitalize = true

        for character in input {
            if shouldCapitalize, character.isLetter {
                result.append(String(character).uppercased())
                shouldCapitalize = false
            } else {
                result.append(character)
            }

            if ".!?".contains(character) {
                shouldCapitalize = true
            }
        }

        return result
    }
}
