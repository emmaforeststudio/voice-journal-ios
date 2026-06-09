import Foundation

struct OpenAIJournalService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func makeDraft(from audioURL: URL) async throws -> JournalDraft {
        let audioData = try Data(contentsOf: audioURL)
        let requestBody = JournalRequest(audioBase64: audioData.base64EncodedString())

        var request = URLRequest(url: try backendURL().appendingPathComponent("journal"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

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
        guard audioData.count > 1_024 else { return "" }

        let requestBody = JournalRequest(audioBase64: audioData.base64EncodedString())
        var request = URLRequest(url: try backendURL().appendingPathComponent("preview"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

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

private struct JournalRequest: Encodable {
    let audioBase64: String
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
            "The Voice Journal backend URL is not configured."
        case .invalidResponse:
            "The Voice Journal backend returned an invalid response."
        case .backend(let message):
            message
        }
    }
}
