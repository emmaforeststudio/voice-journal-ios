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
    private let firstPreviewChunkDuration: TimeInterval = 5
    private let previewChunkDuration: TimeInterval = 10
    private let previewChunkOverlap: TimeInterval = 1
    private var previewSessionID = UUID()
    private var previewSequence = 0
    private var lastPreviewChunkEnd: TimeInterval = 0
    private var nextPreviewChunkEnd: TimeInterval = 10

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
        resetPreviewSession()
        isStartingRecording = true
        Task {
            defer { isStartingRecording = false }
            do {
                try await recorder.start()
                isReadyToRecord = true
                startRecordingTimer()
                if isLivePreviewEnabled {
                    startPreviewTimer()
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
                if error as? RecordingError == .noAudibleAudio {
                    draft = nil
                } else if let previewDraft = makeDraftFromLivePreview(latestLiveTranscript, notice: "This journal was created from the live preview transcript.") {
                    draft = previewDraft
                } else {
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
                resetPreviewSession(startingAt: recorder.currentRecordingTime)
                startPreviewTimer()
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
        previewTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshLivePreview()
            }
    }

    private func stopPreviewTimer() {
        previewTimer?.cancel()
        previewTimer = nil
        isLoadingPreview = false
    }

    private func resetPreviewSession(startingAt startTime: TimeInterval = 0) {
        previewSessionID = UUID()
        previewSequence = 0
        lastPreviewChunkEnd = max(0, startTime)
        nextPreviewChunkEnd = lastPreviewChunkEnd + firstPreviewChunkDuration
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
        guard isLivePreviewEnabled, !isLoadingPreview, isRecording else { return }
        let currentTime = recorder.currentRecordingTime
        guard currentTime >= nextPreviewChunkEnd else { return }

        let chunkStartTime = max(0, lastPreviewChunkEnd - previewChunkOverlap)
        let chunkEndTime = nextPreviewChunkEnd
        isLoadingPreview = true

        Task {
            defer { isLoadingPreview = false }
            do {
                guard let chunkData = try recorder.audioChunkData(from: chunkStartTime, to: chunkEndTime) else {
                    return
                }
                let transcript = try await openAIJournalService.previewTranscript(
                    fromAudioData: chunkData,
                    sessionID: previewSessionID,
                    sequence: previewSequence,
                    chunkStartTime: chunkStartTime,
                    chunkEndTime: chunkEndTime
                )
                let mergedTranscript = mergedLiveTranscript(existing: liveTranscript, incoming: transcript)
                if !mergedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    liveTranscript = mergedTranscript
                    livePreviewNotice = nil
                }
                lastPreviewChunkEnd = chunkEndTime
                nextPreviewChunkEnd = chunkEndTime + previewChunkDuration
                previewSequence += 1
            } catch {
                livePreviewNotice = "Live preview cannot reach the transcription service. Your audio is still recording."
            }
        }
    }

    private func mergedLiveTranscript(existing: String, incoming: String) -> String {
        let previous = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return previous }
        guard !previous.isEmpty else { return next }

        if normalizedPreviewText(next).hasPrefix(normalizedPreviewText(previous)) || next.count >= previous.count * 2 {
            return next
        }

        if previous.contains(next) {
            return previous
        }

        let previousWords = previewWordSpans(in: previous)
        let nextWords = previewWordSpans(in: next)
        let maxOverlap = min(20, previousWords.count, nextWords.count)

        if maxOverlap > 0 {
            for count in stride(from: maxOverlap, through: 1, by: -1) {
                let previousSlice = previousWords.suffix(count).map(\.text)
                let nextSlice = nextWords.prefix(count).map(\.text)
                if previousSlice.elementsEqual(nextSlice), let end = nextWords.prefix(count).last?.end {
                    return joinedPreviewTranscript(previous, String(next[end...]))
                }
            }
        }

        return joinedPreviewTranscript(previous, next)
    }

    private func previewWordSpans(in text: String) -> [(text: String, end: String.Index)] {
        text.matches(of: /[\p{Letter}\p{Number}]+/).map { match in
            (
                text: normalizedPreviewText(String(match.output)),
                end: match.range.upperBound
            )
        }
    }

    private func normalizedPreviewText(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func joinedPreviewTranscript(_ previous: String, _ incoming: String) -> String {
        let next = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return previous }

        let punctuation = CharacterSet(charactersIn: ".,!?;:'\")]}")
        if next.unicodeScalars.first.map({ punctuation.contains($0) }) == true {
            return previous + next
        }
        return previous + " " + next
    }
}
