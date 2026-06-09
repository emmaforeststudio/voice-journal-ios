import Combine
import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var draft: JournalDraft?
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published private(set) var isReadyToRecord = false
    @Published private(set) var isStartingRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var liveTranscript = ""
    @Published private(set) var liveTranscriptLanguage: JournalLanguage?

    let recorder = AudioRecorder()
    private let openAIJournalService = OpenAIJournalService()
    private let transcriber = SpeechTranscriber()
    private let processor = JournalProcessor()
    private var recordingTimer: AnyCancellable?

    var isRecording: Bool {
        recorder.isRecording
    }

    func prepareForRecording() {
        guard !isReadyToRecord, !isStartingRecording, !isRecording else { return }
        Task {
            do {
                try await recorder.prepare()
                isReadyToRecord = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
        liveTranscript = ""
        liveTranscriptLanguage = nil
        isStartingRecording = true
        Task {
            defer { isStartingRecording = false }
            do {
                try await recorder.start { [weak self] transcript, language in
                    self?.liveTranscript = transcript
                    self?.liveTranscriptLanguage = language
                }
                isReadyToRecord = true
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
                isReadyToRecord = false
                do {
                    draft = try await openAIJournalService.makeDraft(from: url)
                } catch {
                    let fallback = try await transcriber.transcribeAudioAutomatically(at: url)
                    var fallbackDraft = processor.makeDraft(from: fallback.text, language: fallback.language)
                    fallbackDraft.notice = "OpenAI enhancement was unavailable, so this journal was transcribed and processed on your iPhone. \(error.localizedDescription)"
                    draft = fallbackDraft
                }
            } catch {
                errorMessage = error.localizedDescription
                draft = JournalDraft(
                    title: "Untitled Journal",
                    body: "",
                    journalDate: .now,
                    emoji: "🙂",
                    language: .english,
                    notice: "The recording finished, but speech transcription was unavailable: \(error.localizedDescription) You can type your journal below and save it."
                )
            }
            isProcessing = false
            liveTranscript = ""
            liveTranscriptLanguage = nil
            prepareForRecording()
            objectWillChange.send()
        }
    }

    func createManualDraft() {
        draft = JournalDraft(
            title: "Untitled Journal",
            body: "",
            journalDate: .now,
            emoji: "🙂",
            language: .english,
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
