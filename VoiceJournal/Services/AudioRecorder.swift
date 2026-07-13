import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var hasDetectedAudio = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTask: Task<Void, Never>?

    var currentRecordingURL: URL? {
        recordingURL
    }

    var currentRecordingTime: TimeInterval {
        audioRecorder?.currentTime ?? 0
    }

    func prepare() async throws {
        guard !isRecording else { return }

        let granted = await requestMicrophonePermission()
        guard granted else { throw RecordingError.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
    }

    func start() async throws {
        try await prepare()

        let url = Self.temporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder.isMeteringEnabled = true
        guard audioRecorder.prepareToRecord(), audioRecorder.record() else {
            throw RecordingError.couldNotStart
        }

        inputLevel = 0
        hasDetectedAudio = false

        self.audioRecorder = audioRecorder
        self.recordingURL = url
        isRecording = true
        startMetering()
    }

    func stop() throws -> URL {
        guard let recordingURL, let audioRecorder else { throw RecordingError.notRecording }

        meterTask?.cancel()
        meterTask = nil
        let recordedDuration = audioRecorder.currentTime
        audioRecorder.stop()
        self.audioRecorder = nil
        self.recordingURL = nil
        isRecording = false
        inputLevel = 0
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard recordedDuration > 0.35 else {
            deleteRecording(at: recordingURL)
            throw RecordingError.noAudibleAudio
        }
        return recordingURL
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func audioChunkData(from startTime: TimeInterval, to endTime: TimeInterval) throws -> Data? {
        guard let recordingURL else { throw RecordingError.notRecording }
        let fileData = try Data(contentsOf: recordingURL)
        guard let dataOffset = Self.wavDataOffset(in: fileData), fileData.count > dataOffset else {
            throw RecordingError.audioChunkUnavailable
        }

        let byteRate = 44_100 * 1 * 16 / 8
        let blockAlign = 1 * 16 / 8
        let startByte = dataOffset + Self.alignedByteOffset(for: max(0, startTime), byteRate: byteRate, blockAlign: blockAlign)
        let endByte = min(
            fileData.count,
            dataOffset + Self.alignedByteOffset(for: max(startTime, endTime), byteRate: byteRate, blockAlign: blockAlign)
        )

        guard endByte > startByte + byteRate / 2 else { return nil }
        let pcmData = fileData.subdata(in: startByte..<endByte)
        return Self.wavData(fromPCMData: pcmData)
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

    private static func wavDataOffset(in data: Data) -> Int? {
        let marker = Data([0x64, 0x61, 0x74, 0x61])
        guard let markerRange = data.range(of: marker), markerRange.upperBound + 4 <= data.count else {
            return nil
        }
        return markerRange.upperBound + 4
    }

    private static func alignedByteOffset(for time: TimeInterval, byteRate: Int, blockAlign: Int) -> Int {
        let byteOffset = max(0, Int(time * Double(byteRate)))
        return byteOffset - byteOffset % blockAlign
    }

    private static func wavData(fromPCMData pcmData: Data) -> Data {
        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32LittleEndian(UInt32(36 + pcmData.count))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LittleEndian(16)
        data.appendUInt16LittleEndian(1)
        data.appendUInt16LittleEndian(1)
        data.appendUInt32LittleEndian(44_100)
        data.appendUInt32LittleEndian(44_100 * 1 * 16 / 8)
        data.appendUInt16LittleEndian(1 * 16 / 8)
        data.appendUInt16LittleEndian(16)
        data.appendASCII("data")
        data.appendUInt32LittleEndian(UInt32(pcmData.count))
        data.append(pcmData)
        return data
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let audioRecorder = self.audioRecorder else { return }
                audioRecorder.updateMeters()
                let decibels = audioRecorder.averagePower(forChannel: 0)
                let level = pow(10, decibels / 20)
                self.inputLevel = level
                if level > 0.002 {
                    self.hasDetectedAudio = true
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

enum RecordingError: LocalizedError {
    case microphoneDenied
    case notReady
    case couldNotStart
    case notRecording
    case noAudibleAudio
    case audioChunkUnavailable

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
        case .noAudibleAudio:
            "The microphone captured silence. Check that Flara Day has microphone access, disconnect any unused Bluetooth microphone, and try again."
        case .audioChunkUnavailable:
            "Live preview could not prepare the latest audio chunk."
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendUInt16LittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
