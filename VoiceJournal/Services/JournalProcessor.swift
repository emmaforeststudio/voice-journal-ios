import Foundation

struct JournalProcessor {
    static let supportedMoodEmojis = ["🙂", "😊", "🥲", "😌", "😔", "😤", "🥰", "🤔", "😴", "✨"]

    func makeDraft(from rawText: String, language: JournalLanguage, date: Date = .now) -> JournalDraft {
        let cleaned = clean(rawText, language: language)
        return JournalDraft(
            title: makeTitle(from: cleaned, language: language),
            body: cleaned,
            journalDate: date,
            emoji: moodEmoji(from: cleaned, language: language),
            language: language,
            notice: nil
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
        case .korean, .japanese, .german, .french, .spanish, .other:
            break
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
            return makeEnglishTitle(from: trimmed, firstSentence: firstSentence)
        case .chinese:
            return makeChineseTitle(from: trimmed, firstSentence: firstSentence)
        case .korean, .japanese, .german, .french, .spanish, .other:
            return String(firstSentence.prefix(40))
        }
    }

    func moodEmoji(from body: String, language: JournalLanguage) -> String {
        let lowered = body.lowercased()

        switch language {
        case .english:
            if containsAny(lowered, ["exhausted", "tired", "sleepy", "drained", "worn out"]) {
                return "😴"
            }

            if containsAny(lowered, ["angry", "frustrated", "annoyed", "upset", "mad"]) {
                return "😤"
            }

            if containsAny(lowered, ["sad", "lonely", "disappointed", "hurt", "bad mood"]) {
                return "😔"
            }

            if containsAny(lowered, ["anxious", "worried", "nervous", "uncertain", "confused", "thinking"]) {
                return "🤔"
            }

            if containsAny(lowered, ["grateful", "thankful", "love", "loved", "sweet", "heart"]) {
                return "🥰"
            }

            if containsAny(lowered, ["proud", "finished", "completed", "accomplished", "productive"]) {
                return "✨"
            }

            if containsAny(lowered, ["good", "happy", "excited", "hopeful", "hopefully", "great", "better"]) {
                return "😊"
            }

            if containsAny(lowered, ["calm", "peaceful", "relieved", "okay", "fine"]) {
                return "😌"
            }

            return "🙂"
        case .chinese:
            if containsAny(body, ["累", "困", "疲惫", "没精神"]) {
                return "😴"
            }

            if containsAny(body, ["生气", "烦", "崩溃", "委屈"]) {
                return "😤"
            }

            if containsAny(body, ["难过", "伤心", "失落", "孤单"]) {
                return "😔"
            }

            if containsAny(body, ["担心", "焦虑", "紧张", "迷茫"]) {
                return "🤔"
            }

            if containsAny(body, ["感谢", "感恩", "喜欢", "爱", "温暖"]) {
                return "🥰"
            }

            if containsAny(body, ["完成", "做完", "进步", "不错", "有成就"]) {
                return "✨"
            }

            if containsAny(body, ["开心", "高兴", "期待", "希望", "很好", "顺利"]) {
                return "😊"
            }

            if containsAny(body, ["平静", "放松", "安心"]) {
                return "😌"
            }

            return "🙂"
        case .korean, .japanese, .german, .french, .spanish, .other:
            return "🙂"
        }
    }

    func dailyMoodEmoji(from emojis: [String]) -> String? {
        guard !emojis.isEmpty else { return nil }

        let scores: [String: Double] = [
            "🥰": 2, "😊": 2, "✨": 2,
            "🙂": 1, "😌": 0.75,
            "🤔": 0, "🥲": -0.5,
            "😴": -1, "😔": -2, "😤": -2
        ]
        let average = emojis.map { scores[$0] ?? 0 }.reduce(0, +) / Double(emojis.count)

        switch average {
        case 1.5...:
            return "😊"
        case 0.4..<1.5:
            return "🙂"
        case -0.4..<0.4:
            return "😌"
        case -1.4 ..< -0.4:
            return "🥲"
        default:
            return "😔"
        }
    }

    func normalizedMoodEmoji(_ emoji: String, body: String, language: JournalLanguage) -> String {
        Self.supportedMoodEmojis.contains(emoji) ? emoji : moodEmoji(from: body, language: language)
    }

    private func makeEnglishTitle(from body: String, firstSentence: String) -> String {
        let lowered = body.lowercased()

        if containsAll(lowered, ["test", "voice journal"])
            || containsAll(lowered, ["testing", "voice journal"])
            || containsAll(lowered, ["test", "flara day"])
            || containsAll(lowered, ["testing", "flara day"]) {
            return "Testing Flara Day"
        }

        if containsAll(lowered, ["good", "day"]) || containsAll(lowered, ["great", "day"]) {
            return "A Good Day"
        }

        if containsAny(lowered, ["grateful", "thankful"]) {
            return "Feeling Grateful"
        }

        if containsAny(lowered, ["anxious", "worried", "nervous"]) {
            return "Working Through Worry"
        }

        if containsAny(lowered, ["tired", "exhausted", "drained"]) {
            return "A Tired Check-In"
        }

        if containsAny(lowered, ["finished", "completed", "accomplished"]) {
            return "A Small Win"
        }

        let wordsToDrop = Set(["hey", "hi", "hello", "so", "well", "today", "i", "i'm", "im", "am", "was", "wanted", "want", "to", "just", "really"])
        let words = firstSentence
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { !$0.isEmpty && !wordsToDrop.contains($0) }

        let titleWords = words.prefix(5).map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }

        return titleWords.isEmpty ? "Journal Check-In" : titleWords.joined(separator: " ")
    }

    private func makeChineseTitle(from body: String, firstSentence: String) -> String {
        if containsAll(body, ["测试", "语音"]) || containsAll(body, ["测试", "日记"]) {
            return "测试语音日记"
        }

        if containsAny(body, ["感谢", "感恩"]) {
            return "感恩的一天"
        }

        if containsAny(body, ["焦虑", "担心", "紧张"]) {
            return "整理焦虑"
        }

        if containsAny(body, ["累", "疲惫", "困"]) {
            return "有点累的一天"
        }

        if containsAny(body, ["完成", "做完", "进步"]) {
            return "今天的小成就"
        }

        return String(firstSentence.prefix(10))
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func containsAll(_ text: String, _ terms: [String]) -> Bool {
        terms.allSatisfy { text.contains($0) }
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
        text = text.replacingOccurrences(of: "([.!?])[ \\t]*([A-Za-z])", with: "$1 $2", options: .regularExpression)

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
