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
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func prepare() async throws {
        guard !isRecording else { return }

        let granted = await requestMicrophonePermission()
        guard granted else { throw RecordingError.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        _ = await requestSpeechAuthorization()
    }

    func start(onLiveTranscript: @escaping (String) -> Void) async throws {
        try await prepare()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw RecordingError.notReady }

        let url = Self.temporaryRecordingURL()
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let recognitionRequest = await makeLiveRecognitionRequest(onLiveTranscript: onLiveTranscript)

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            try? audioFile.write(from: buffer)
            recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        self.audioFile = audioFile
        self.recordingURL = url
        self.recognitionRequest = recognitionRequest
        isRecording = true
    }

    func stop() throws -> URL {
        guard let recordingURL else { throw RecordingError.notRecording }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
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

    private func makeLiveRecognitionRequest(onLiveTranscript: @escaping (String) -> Void) async -> SFSpeechAudioBufferRecognitionRequest? {
        let authorization = await requestSpeechAuthorization()
        guard authorization == .authorized else { return nil }

        let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { return nil }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            guard error == nil, let result else { return }
            Task { @MainActor in
                onLiveTranscript(result.bestTranscription.formattedString)
            }
        }

        return request
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
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
