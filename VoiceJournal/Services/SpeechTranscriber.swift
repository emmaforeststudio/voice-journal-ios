import Combine
import Foundation
import Speech

@MainActor
final class SpeechTranscriber: ObservableObject {
    private let automaticTranscriptionLanguages: [JournalLanguage] = [
        .english,
        .chinese,
        .korean,
        .spanish,
        .french,
        .german,
        .japanese
    ]

    func transcribeAudioAutomatically(at url: URL) async throws -> (text: String, language: JournalLanguage) {
        let results = await withTaskGroup(of: (JournalLanguage, String)?.self) { group in
            for language in automaticTranscriptionLanguages {
                group.addTask { [url] in
                    do {
                        let text = try await self.transcribeAudio(at: url, language: language)
                        return (language, text)
                    } catch {
                        return nil
                    }
                }
            }

            var values: [(language: JournalLanguage, text: String)] = []
            for await result in group {
                guard let result else { continue }
                values.append(result)
            }
            return values
        }

        if let best = results
            .filter({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .max(by: { transcriptionScore($0.text, language: $0.language) < transcriptionScore($1.text, language: $1.language) }) {
            return (best.text, best.language)
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

    private func transcriptionScore(_ text: String, language: JournalLanguage) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let scriptBonus: Int
        switch language {
        case .chinese:
            scriptBonus = trimmed.hanCharacterCount * 8
        case .korean:
            scriptBonus = trimmed.hangulCharacterCount * 8
        case .japanese:
            scriptBonus = trimmed.kanaCharacterCount * 8 + trimmed.hanCharacterCount * 2
        default:
            scriptBonus = 0
        }

        return trimmed.count + scriptBonus
    }
}

private extension String {
    var hanCharacterCount: Int {
        unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }.count
    }

    var hangulCharacterCount: Int {
        unicodeScalars.filter { scalar in
            (0xAC00...0xD7AF).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value)
        }.count
    }

    var kanaCharacterCount: Int {
        unicodeScalars.filter { scalar in
            (0x3040...0x30FF).contains(scalar.value)
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
