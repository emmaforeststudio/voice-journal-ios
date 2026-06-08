import Combine
import Foundation
import Speech

@MainActor
final class SpeechTranscriber: ObservableObject {
    func transcribeAudioAutomatically(at url: URL) async throws -> (text: String, language: JournalLanguage) {
        async let englishResult = try? transcribeAudio(at: url, language: .english)
        async let chineseResult = try? transcribeAudio(at: url, language: .chinese)

        let (english, chinese) = await (englishResult, chineseResult)
        if let chinese, chinese.hanCharacterCount >= 2 {
            return (chinese, .chinese)
        }

        if let english, !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (english, .english)
        }

        if let chinese, !chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (chinese, .chinese)
        }

        throw SpeechTranscriptionError.emptyResult
    }

    func transcribeAudio(at url: URL, language: JournalLanguage) async throws -> String {
        let authorization = await requestSpeechAuthorization()
        guard authorization == .authorized else { throw SpeechTranscriptionError.permissionDenied }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)) else {
            throw SpeechTranscriptionError.unsupportedLanguage
        }

        let request = SFSpeechURLRecognitionRequest(url: url)

#if targetEnvironment(simulator)
        // The simulator does not advertise on-device recognition. Allow Apple's
        // standard recognizer so the complete recording flow can be tested.
        request.requiresOnDeviceRecognition = false
#else
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechTranscriptionError.onDeviceUnavailable
        }
        request.requiresOnDeviceRecognition = true
#endif
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var task: SFSpeechRecognitionTask?

            task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard !didResume else { return }
                    didResume = true
                    task = nil
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }
                guard !didResume else { return }
                didResume = true
                task = nil
                continuation.resume(returning: result.bestTranscription.formattedString)
            }

            if task?.state == .completed, !didResume {
                didResume = true
                task = nil
                continuation.resume(throwing: SpeechTranscriptionError.emptyResult)
            }
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private extension String {
    var hanCharacterCount: Int {
        unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }.count
    }
}

enum SpeechTranscriptionError: LocalizedError {
    case permissionDenied
    case unsupportedLanguage
    case onDeviceUnavailable
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Speech recognition permission is required to transcribe locally."
        case .unsupportedLanguage:
            "This language is not available for speech recognition on this device."
        case .onDeviceUnavailable:
            "On-device speech recognition is not available for this language on this device."
        case .emptyResult:
            "No speech was detected in the recording."
        }
    }
}
