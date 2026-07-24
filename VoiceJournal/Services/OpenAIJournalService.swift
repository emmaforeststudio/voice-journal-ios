import Foundation

@MainActor
struct OpenAIJournalService {
    private let session: URLSession
    private let finalChunkDuration: TimeInterval = 6 * 60
    private let finalChunkOverlap: TimeInterval = 2

    init(session: URLSession = .shared) {
        self.session = session
    }

    func makeDraft(from audioURL: URL, livePreviewTranscript: String = "") async throws -> JournalDraft {
        let duration = try AudioRecorder.duration(of: audioURL)
        try VoiceUsageTracker.recordTranscription(duration: duration)

        if duration > finalChunkDuration {
            let transcript = try await transcribeRecordingInChunks(from: audioURL, duration: duration)
            return try await makeDraft(
                fromTranscript: transcript,
                livePreviewTranscript: livePreviewTranscript
            )
        }

        let audioData = try Data(contentsOf: audioURL)
        let request = try uploadRequest(
            endpoint: "journal",
            audioData: audioData,
            timeout: 120,
            fields: ["livePreviewTranscript": livePreviewTranscript]
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIJournalServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? JSONDecoder().decode(BackendError.self, from: data)
            throw OpenAIJournalServiceError.backend(error?.error ?? "The journal backend returned an error.")
        }

        return try decodedDraft(from: data)
    }

    private func makeDraft(
        fromTranscript transcript: String,
        livePreviewTranscript: String
    ) async throws -> JournalDraft {
        var request = URLRequest(url: try backendURL().appendingPathComponent("journal-text"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            JournalTextRequest(
                transcript: transcript,
                livePreviewTranscript: livePreviewTranscript
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIJournalServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? JSONDecoder().decode(BackendError.self, from: data)
            throw OpenAIJournalServiceError.backend(error?.error ?? "The journal backend returned an error.")
        }

        return try decodedDraft(from: data)
    }

    private func decodedDraft(from data: Data) throws -> JournalDraft {
        let journal = try JSONDecoder().decode(JournalResponse.self, from: data)
        let language = JournalLanguage(rawValue: journal.language) ?? .english
        let emoji = JournalProcessor().normalizedMoodEmoji(journal.emoji, body: journal.body, language: language)
        return JournalDraft(
            title: journal.title,
            body: journal.body,
            journalDate: .now,
            emoji: emoji,
            language: language,
            notice: nil
        )
    }

    func transcribeRecording(from audioURL: URL) async throws -> String {
        let duration = try AudioRecorder.duration(of: audioURL)
        try VoiceUsageTracker.recordTranscription(duration: duration)
        return try await transcribeRecordingInChunks(from: audioURL, duration: duration)
    }

    func translate(title: String, body: String, to language: TranslationLanguage) async throws -> TranslatedContent {
        var request = URLRequest(url: try backendURL().appendingPathComponent("translate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TranslationRequest(title: title, body: body, targetLanguage: language.displayName)
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIJournalServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? JSONDecoder().decode(BackendError.self, from: data)
            throw OpenAIJournalServiceError.backend(error?.error ?? "Translation was unavailable.")
        }
        return try JSONDecoder().decode(TranslatedContent.self, from: data)
    }

    private func transcribeRecordingInChunks(
        from audioURL: URL,
        duration: TimeInterval
    ) async throws -> String {
        if duration <= finalChunkDuration {
            let audioData = try Data(contentsOf: audioURL)
            return try await transcribeAudioData(audioData)
        }

        var transcript = ""
        var chunkStart: TimeInterval = 0
        while chunkStart < duration {
            let chunkEnd = min(duration, chunkStart + finalChunkDuration)
            guard let chunkData = try AudioRecorder.audioChunkData(
                from: audioURL,
                startTime: chunkStart,
                endTime: chunkEnd
            ) else {
                break
            }

            let precedingContext = String(transcript.suffix(1_200))
            let chunkTranscript = try await transcribeAudioData(
                chunkData,
                precedingTranscript: precedingContext
            )
            transcript = mergedTranscript(existing: transcript, incoming: chunkTranscript)
            guard chunkEnd < duration else { break }
            chunkStart = max(0, chunkEnd - finalChunkOverlap)
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIJournalServiceError.backend("No speech was detected in the recording.")
        }
        return transcript
    }

    private func transcribeAudioData(
        _ audioData: Data,
        precedingTranscript: String = ""
    ) async throws -> String {
        let request = try uploadRequest(
            endpoint: "transcription",
            audioData: audioData,
            timeout: 120,
            fields: ["previousTranscript": precedingTranscript]
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIJournalServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? JSONDecoder().decode(BackendError.self, from: data)
            throw OpenAIJournalServiceError.backend(error?.error ?? "Transcription was unavailable.")
        }

        return try JSONDecoder().decode(PreviewResponse.self, from: data).transcript
    }

    private func mergedTranscript(existing: String, incoming: String) -> String {
        let previous = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return previous }
        guard !previous.isEmpty else { return next }
        if previous.contains(next) { return previous }

        let previousWords = previous.split(whereSeparator: \.isWhitespace)
        let nextWords = next.split(whereSeparator: \.isWhitespace)
        let maximumWordOverlap = min(24, previousWords.count, nextWords.count)
        if maximumWordOverlap > 0 {
            for count in stride(from: maximumWordOverlap, through: 1, by: -1) {
                let previousSuffix = previousWords.suffix(count).map(normalizedTranscriptPart)
                let nextPrefix = nextWords.prefix(count).map(normalizedTranscriptPart)
                if previousSuffix.elementsEqual(nextPrefix) {
                    return joinedTranscript(previous, nextWords.dropFirst(count).joined(separator: " "))
                }
            }
        }

        let previousTail = Array(previous.suffix(160))
        let nextHead = Array(next.prefix(160))
        let maximumCharacterOverlap = min(previousTail.count, nextHead.count)
        if maximumCharacterOverlap >= 4 {
            for count in stride(from: maximumCharacterOverlap, through: 4, by: -1) {
                if normalizedTranscriptPart(String(previousTail.suffix(count))) ==
                    normalizedTranscriptPart(String(nextHead.prefix(count))) {
                    return joinedTranscript(previous, String(next.dropFirst(count)))
                }
            }
        }

        return joinedTranscript(previous, next)
    }

    private func normalizedTranscriptPart<S: StringProtocol>(_ value: S) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func joinedTranscript(_ first: String, _ second: String) -> String {
        let next = second.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return first }
        return "\(first) \(next)"
    }

    func previewTranscript(
        fromAudioData audioData: Data,
        sessionID: UUID,
        sequence: Int,
        chunkStartTime: TimeInterval,
        chunkEndTime: TimeInterval
    ) async throws -> String {
        try await previewTranscript(
            fromAudioData: audioData,
            sessionID: sessionID.uuidString,
            sequence: sequence,
            chunkStartTime: chunkStartTime,
            chunkEndTime: chunkEndTime
        )
    }

    private func previewTranscript(
        fromAudioData audioData: Data,
        sessionID: String? = nil,
        sequence: Int? = nil,
        chunkStartTime: TimeInterval? = nil,
        chunkEndTime: TimeInterval? = nil
    ) async throws -> String {
        guard audioData.count > 1_024 else { return "" }

        let fields = [
            "sessionId": sessionID ?? "",
            "sequence": sequence.map { String($0) } ?? "",
            "chunkStartTime": chunkStartTime.map { String($0) } ?? "",
            "chunkEndTime": chunkEndTime.map { String($0) } ?? ""
        ]
        let request = try uploadRequest(
            endpoint: "preview",
            audioData: audioData,
            timeout: 30,
            fields: fields
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIJournalServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? JSONDecoder().decode(BackendError.self, from: data)
            throw OpenAIJournalServiceError.backend(error?.error ?? "Live transcription was unavailable.")
        }

        return try JSONDecoder().decode(PreviewResponse.self, from: data).transcript
    }

    private func uploadRequest(
        endpoint: String,
        audioData: Data,
        timeout: TimeInterval,
        fields: [String: String]
    ) throws -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: try backendURL().appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            fields: fields,
            audioData: audioData
        )
        return request
    }

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        audioData: Data
    ) -> Data {
        var body = Data()
        for (name, value) in fields where !value.isEmpty {
            body.appendMultipartString("--\(boundary)\r\n")
            body.appendMultipartString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendMultipartString("\(value)\r\n")
        }

        body.appendMultipartString("--\(boundary)\r\n")
        body.appendMultipartString("Content-Disposition: form-data; name=\"audio\"; filename=\"journal.wav\"\r\n")
        body.appendMultipartString("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.appendMultipartString("\r\n--\(boundary)--\r\n")
        return body
    }

    private func backendURL() throws -> URL {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "VoiceJournalBackendURL") as? String,
            let url = URL(string: value)
        else {
            throw OpenAIJournalServiceError.missingBackendURL
        }

        return url
    }
}

private struct JournalResponse: Decodable {
    let title: String
    let body: String
    let emoji: String
    let language: String
}

private struct JournalTextRequest: Encodable {
    let transcript: String
    let livePreviewTranscript: String
}

private struct TranslationRequest: Encodable {
    let title: String
    let body: String
    let targetLanguage: String
}

struct TranslatedContent: Codable, Equatable {
    let title: String
    let body: String
}

private struct PreviewResponse: Decodable {
    let transcript: String
}

private struct BackendError: Decodable {
    let error: String
}

enum OpenAIJournalServiceError: LocalizedError {
    case missingBackendURL
    case invalidResponse
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .missingBackendURL:
            "The Flara Day backend URL is not configured."
        case .invalidResponse:
            "The Flara Day backend returned an invalid response."
        case .backend(let message):
            message
        }
    }
}

private extension Data {
    mutating func appendMultipartString(_ string: String) {
        append(Data(string.utf8))
    }
}
