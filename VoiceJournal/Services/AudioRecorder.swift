import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?

    func prepare() async throws {
        guard recorder == nil else { return }

        let granted = await requestMicrophonePermission()
        guard granted else { throw RecordingError.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = Self.temporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        self.recorder = recorder
    }

    func start() async throws {
        try await prepare()
        guard let recorder else { throw RecordingError.notReady }
        guard recorder.record() else { throw RecordingError.couldNotStart }
        isRecording = true
    }

    func stop() throws -> URL {
        guard let recorder else { throw RecordingError.notRecording }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recorder.url
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
            .appendingPathExtension("m4a")
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
