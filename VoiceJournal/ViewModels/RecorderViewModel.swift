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
    @Published private(set) var livePreviewNotice: String?

    let recorder = AudioRecorder()
    private let openAIJournalService = OpenAIJournalService()
    private let transcriber = SpeechTranscriber()
    private let processor = JournalProcessor()
    private var recordingTimer: AnyCancellable?
    private var previewTimer: AnyCancellable?
    private var recorderObservation: AnyCancellable?
    private var isLoadingPreview = false
    private var isLivePreviewEnabled = true

    init() {
        recorderObservation = recorder.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    var isRecording: Bool {
        recorder.isRecording
    }

    var microphoneLevel: Float {
        recorder.inputLevel
    }

    var hasDetectedAudio: Bool {
        recorder.hasDetectedAudio
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
        livePreviewNotice = nil
        isStartingRecording = true
        Task {
            defer { isStartingRecording = false }
            do {
                try await recorder.start()
                isReadyToRecord = true
                startRecordingTimer()
                if isLivePreviewEnabled {
                    startPreviewTimer()
                    scheduleInitialPreview()
                }
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
        stopPreviewTimer()
        let latestLiveTranscript = liveTranscript

        Task {
            do {
                let url = try recorder.stop()
                defer { recorder.deleteRecording(at: url) }
                isReadyToRecord = false
                do {
                    draft = try await openAIJournalService.makeDraft(
                        from: url,
                        livePreviewTranscript: latestLiveTranscript
                    )
                } catch {
                    if let previewDraft = makeDraftFromLivePreview(latestLiveTranscript, notice: "This journal was created from the live preview transcript.") {
                        draft = previewDraft
                    } else {
                        let fallback = try await transcriber.transcribeAudioAutomatically(at: url)
                        var fallbackDraft = processor.makeDraft(from: fallback.text, language: fallback.language)
                        fallbackDraft.notice = "OpenAI enhancement was unavailable, so this journal was transcribed and processed on your iPhone. \(error.localizedDescription)"
                        draft = fallbackDraft
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                if let previewDraft = makeDraftFromLivePreview(latestLiveTranscript, notice: "This journal was created from the live preview transcript.") {
                    draft = previewDraft
                } else if error as? RecordingError != .noAudibleAudio {
                    draft = JournalDraft(
                        title: "Untitled Journal",
                        body: "",
                        journalDate: .now,
                        emoji: "🙂",
                        language: .english,
                        notice: "The recording finished, but speech transcription was unavailable: \(error.localizedDescription) You can type your journal below and save it."
                    )
                }
            }
            isProcessing = false
            liveTranscript = ""
            livePreviewNotice = nil
            prepareForRecording()
            objectWillChange.send()
        }
    }

    func cancelRecording() {
        errorMessage = nil
        isProcessing = false
        stopRecordingTimer()
        stopPreviewTimer()
        if isRecording {
            do {
                let url = try recorder.stop()
                recorder.deleteRecording(at: url)
            } catch {
                errorMessage = nil
            }
        }
        liveTranscript = ""
        livePreviewNotice = nil
        prepareForRecording()
        objectWillChange.send()
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

    func updateLivePreviewEnabled(_ isEnabled: Bool) {
        isLivePreviewEnabled = isEnabled
        if isRecording {
            if isEnabled {
                startPreviewTimer()
                scheduleInitialPreview()
            } else {
                stopPreviewTimer()
                livePreviewNotice = nil
            }
        }
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

    private func startPreviewTimer() {
        previewTimer?.cancel()
        previewTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshLivePreview()
            }
    }

    private func scheduleInitialPreview() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refreshLivePreview()
        }
    }

    private func stopPreviewTimer() {
        previewTimer?.cancel()
        previewTimer = nil
        isLoadingPreview = false
    }

    private func makeDraftFromLivePreview(_ livePreviewTranscript: String, notice: String) -> JournalDraft? {
        let text = livePreviewTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let language = detectedLanguage(from: text)
        var previewDraft = processor.makeDraft(from: text, language: language)
        previewDraft.notice = notice
        return previewDraft
    }

    private func detectedLanguage(from text: String) -> JournalLanguage {
        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return .chinese
        }
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            return .japanese
        }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) {
            return .korean
        }
        return .english
    }

    private func refreshLivePreview() {
        guard isLivePreviewEnabled, !isLoadingPreview, isRecording, let url = recorder.currentRecordingURL else { return }
        isLoadingPreview = true

        Task {
            defer { isLoadingPreview = false }
            do {
                let transcript = try await openAIJournalService.previewTranscript(from: url)
                if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    liveTranscript = transcript
                    livePreviewNotice = nil
                }
            } catch {
                livePreviewNotice = "Live preview cannot reach the transcription service. Your audio is still recording."
            }
        }
    }
}
