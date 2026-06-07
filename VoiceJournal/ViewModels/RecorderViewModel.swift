import Combine
import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var selectedLanguage: JournalLanguage = .english
    @Published var draft: JournalDraft?
    @Published var errorMessage: String?
    @Published var isProcessing = false

    let recorder = AudioRecorder()
    private let transcriber = SpeechTranscriber()
    private let processor = JournalProcessor()

    var isRecording: Bool {
        recorder.isRecording
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        errorMessage = nil
        Task {
            do {
                try await recorder.start()
                objectWillChange.send()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopRecording() {
        errorMessage = nil
        isProcessing = true

        Task {
            do {
                let url = try recorder.stop()
                defer { recorder.deleteRecording(at: url) }
                let transcript = try await transcriber.transcribeAudio(at: url, language: selectedLanguage)
                draft = processor.makeDraft(from: transcript, language: selectedLanguage)
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
            objectWillChange.send()
        }
    }

    func createManualDraft() {
        draft = JournalDraft(
            title: "Untitled Journal",
            body: "",
            journalDate: .now,
            emoji: "🙂",
            language: selectedLanguage
        )
    }
}
