import Foundation

struct OpenAIJournalService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func makeDraft(from audioURL: URL, livePreviewTranscript: String = "") async throws -> JournalDraft {
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

    func previewTranscript(from audioURL: URL) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        return try await previewTranscript(fromAudioData: audioData)
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
