import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recognitionRequests: [SFSpeechAudioBufferRecognitionRequest] = []
    private var recognitionTasks: [SFSpeechRecognitionTask] = []
    private var liveCandidates: [JournalLanguage: LiveTranscriptCandidate] = [:]

    func prepare() async throws {
        guard !isRecording else { return }

        let granted = await requestMicrophonePermission()
        guard granted else { throw RecordingError.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        _ = await requestSpeechAuthorization()
    }

    func start(onLiveTranscript: @escaping (String, JournalLanguage) -> Void) async throws {
        try await prepare()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw RecordingError.notReady }

        let url = Self.temporaryRecordingURL()
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let recognitionRequests = await makeLiveRecognitionRequests(onLiveTranscript: onLiveTranscript)

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            try? audioFile.write(from: buffer)
            recognitionRequests.forEach { $0.append(buffer) }
        }

        audioEngine.prepare()
        try audioEngine.start()

        self.audioFile = audioFile
        self.recordingURL = url
        self.recognitionRequests = recognitionRequests
        isRecording = true
    }

    func stop() throws -> URL {
        guard let recordingURL else { throw RecordingError.notRecording }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequests.forEach { $0.endAudio() }
        recognitionTasks.forEach { $0.cancel() }
        recognitionRequests = []
        recognitionTasks = []
        liveCandidates = [:]
        audioFile = nil
        self.recordingURL = nil
        isRecording = false
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recordingURL
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private static func temporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
    }

    private func makeLiveRecognitionRequests(
        onLiveTranscript: @escaping (String, JournalLanguage) -> Void
    ) async -> [SFSpeechAudioBufferRecognitionRequest] {
        let authorization = await requestSpeechAuthorization()
        guard authorization == .authorized else { return [] }

        liveCandidates = [:]
        recognitionTasks = []

        return JournalLanguage.allCases.compactMap { language in
            guard
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)),
                recognizer.isAvailable
            else {
                return nil
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard error == nil, let result else { return }
                Task { @MainActor in
                    self?.updateLiveCandidate(
                        result.bestTranscription,
                        language: language,
                        onLiveTranscript: onLiveTranscript
                    )
                }
            }
            recognitionTasks.append(task)
            return request
        }
    }

    private func updateLiveCandidate(
        _ transcription: SFTranscription,
        language: JournalLanguage,
        onLiveTranscript: @escaping (String, JournalLanguage) -> Void
    ) {
        let text = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let confidences = transcription.segments.map(\.confidence).filter { $0 > 0 }
        let confidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)
        liveCandidates[language] = LiveTranscriptCandidate(text: text, language: language, confidence: confidence)

        guard let best = liveCandidates.values.max(by: { $0.score < $1.score }), best.score >= 3 else {
            return
        }

        let runnerUpScore = liveCandidates.values
            .filter { $0.language != best.language }
            .map(\.score)
            .max() ?? 0
        guard best.score - runnerUpScore >= 0.75 else { return }

        onLiveTranscript(best.text, best.language)
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private struct LiveTranscriptCandidate {
    let text: String
    let language: JournalLanguage
    let confidence: Float

    var score: Double {
        let lowered = " \(text.lowercased()) "
        let scalarCount = max(text.unicodeScalars.count, 1)
        let hanCount = text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let latinCount = text.unicodeScalars.filter {
            (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
        }.count

        switch language {
        case .english:
            let commonWords = [" i ", " the ", " is ", " am ", " to ", " and ", " this ", " that ", " feel ", " today "]
            let wordEvidence = commonWords.filter { lowered.contains($0) }.count
            return Double(confidence) * 4
                + Double(latinCount) / Double(scalarCount) * 2
                + Double(wordEvidence) * 0.75
                - Double(hanCount) / Double(scalarCount) * 4
        case .chinese:
            let commonTerms = ["我", "的", "是", "了", "想", "今天", "因为", "这个", "很", "不", "觉得", "开心"]
            let termEvidence = commonTerms.filter { text.contains($0) }.count
            return Double(confidence) * 4
                + Double(hanCount) / Double(scalarCount) * 2
                + Double(termEvidence) * 0.75
                - Double(latinCount) / Double(scalarCount)
        }
    }
}

enum RecordingError: LocalizedError {
    case microphoneDenied
    case notReady
    case couldNotStart
    case notRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone permission is required to record a journal."
        case .notReady:
            "The microphone is not ready yet."
        case .couldNotStart:
            "The recording could not start."
        case .notRecording:
            "There is no active recording to stop."
        }
    }
}
