import Combine
import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var selectedLanguage: JournalLanguage = .english
    @Published var draft: JournalDraft?
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    let recorder = AudioRecorder()
    private let transcriber = SpeechTranscriber()
    private let processor = JournalProcessor()
    private var recordingTimer: AnyCancellable?

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
                startRecordingTimer()
                objectWillChange.send()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopRecording() {
        errorMessage = nil
        isProcessing = true
        stopRecordingTimer()

        Task {
            do {
                let url = try recorder.stop()
                defer { recorder.deleteRecording(at: url) }
                let transcript = try await transcriber.transcribeAudio(at: url, language: selectedLanguage)
                draft = processor.makeDraft(from: transcript, language: selectedLanguage)
            } catch {
                errorMessage = error.localizedDescription
                draft = JournalDraft(
                    title: "Untitled Journal",
                    body: "",
                    journalDate: .now,
                    emoji: "🙂",
                    language: selectedLanguage,
                    notice: "The recording finished, but speech transcription was unavailable: \(error.localizedDescription) You can type your journal below and save it."
                )
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
            language: selectedLanguage,
            notice: nil
        )
    }

    var formattedRecordingDuration: String {
        let totalSeconds = Int(recordingDuration)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.recordingDuration += 1
            }
    }

    private func stopRecordingTimer() {
        recordingTimer?.cancel()
        recordingTimer = nil
    }
}
