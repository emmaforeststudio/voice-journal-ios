import AVFoundation
import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    private static let recordingSampleRate = 16_000
    private static let recordingChannelCount = 1
    private static let recordingBitDepth = 16

    @Published private(set) var isRecording = false
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var hasDetectedAudio = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTask: Task<Void, Never>?
    private var didReachDurationLimit = false
    private var didReportInterruption = false
    private var activeDurationLimit = VoiceUsageTracker.maximumRecordingDuration
    private var activeDurationLimitReason = RecordingDurationLimitReason.perRecording
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    var onRecordingDurationLimitReached: ((RecordingDurationLimitReason) -> Void)?
    var onRecordingInterrupted: ((RecordingInterruptionReason) -> Void)?

    override init() {
        super.init()
        observeAudioSession()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

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
    }

    func start() async throws {
        try await prepare()
        let remainingDuration = VoiceUsageTracker.remainingDuration()
        guard remainingDuration > 0.5 else { throw RecordingError.dailyLimitReached }

        activeDurationLimit = min(VoiceUsageTracker.maximumRecordingDuration, remainingDuration)
        activeDurationLimitReason = remainingDuration < VoiceUsageTracker.maximumRecordingDuration
            ? .daily
            : .perRecording
        didReachDurationLimit = false
        didReportInterruption = false

        let session = AVAudioSession.sharedInstance()
        try await activateRecordingSession(session)

        let url = Self.temporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.recordingSampleRate,
            AVNumberOfChannelsKey: Self.recordingChannelCount,
            AVLinearPCMBitDepthKey: Self.recordingBitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let audioRecorder: AVAudioRecorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = true
            guard audioRecorder.prepareToRecord(), audioRecorder.record() else {
                throw RecordingError.couldNotStart
            }
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: url)
            throw error
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
        let detectedAudioDuringRecording = hasDetectedAudio
        audioRecorder.stop()
        self.audioRecorder = nil
        self.recordingURL = nil
        isRecording = false
        inputLevel = 0
        hasDetectedAudio = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let recordedData = detectedAudioDuringRecording
            ? nil
            : try? Data(contentsOf: recordingURL, options: .mappedIfSafe)
        guard Self.shouldTranscribe(
            recordedDuration: recordedDuration,
            detectedAudioDuringRecording: detectedAudioDuringRecording,
            wavData: recordedData
        ) else {
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
        return try Self.audioChunkData(from: recordingURL, startTime: startTime, endTime: endTime)
    }

    static func audioChunkData(
        from recordingURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) throws -> Data? {
        let file = try FileHandle(forReadingFrom: recordingURL)
        defer { try? file.close() }
        let header = try file.read(upToCount: 4_096) ?? Data()
        guard let dataOffset = Self.wavDataOffset(in: header) else {
            throw RecordingError.audioChunkUnavailable
        }

        let byteRate = recordingSampleRate * recordingChannelCount * recordingBitDepth / 8
        let blockAlign = recordingChannelCount * recordingBitDepth / 8
        let startByte = dataOffset + Self.alignedByteOffset(for: max(0, startTime), byteRate: byteRate, blockAlign: blockAlign)
        let fileSize = Int(try file.seekToEnd())
        let endByte = min(
            fileSize,
            dataOffset + Self.alignedByteOffset(for: max(startTime, endTime), byteRate: byteRate, blockAlign: blockAlign)
        )

        guard endByte > startByte + byteRate / 2 else { return nil }
        try file.seek(toOffset: UInt64(startByte))
        let pcmData = try file.read(upToCount: endByte - startByte) ?? Data()
        guard !pcmData.isEmpty else { return nil }
        return Self.wavData(fromPCMData: pcmData)
    }

    static func duration(of recordingURL: URL) throws -> TimeInterval {
        let audioFile = try AVAudioFile(forReading: recordingURL)
        guard audioFile.fileFormat.sampleRate > 0 else { return 0 }
        return TimeInterval(audioFile.length) / audioFile.fileFormat.sampleRate
    }

    private func activateRecordingSession(_ session: AVAudioSession) async throws {
        do {
            try configureAndActivate(session)
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try await Task.sleep(for: .milliseconds(150))
            try configureAndActivate(session)
        }
    }

    private func configureAndActivate(_ session: AVAudioSession) throws {
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
    }

    private func observeAudioSession() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioSessionInterruption(notification)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioRouteChange(notification)
            }
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard isRecording, !didReportInterruption else { return }
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: rawType) == .began
        else { return }

        reportInterruption(.system)
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard isRecording, !didReportInterruption else { return }
        guard
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
        else { return }

        reportInterruption(.audioInputChanged)
    }

    private func reportInterruption(_ reason: RecordingInterruptionReason) {
        didReportInterruption = true
        if UIApplication.shared.applicationState != .active {
            Task {
                await RecordingStatusNotificationScheduler.scheduleInterruption(reason)
            }
        }
        onRecordingInterrupted?(reason)
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

    static func shouldTranscribe(
        recordedDuration: TimeInterval,
        detectedAudioDuringRecording: Bool,
        wavData: Data?
    ) -> Bool {
        guard recordedDuration > 0.35 else { return false }
        if detectedAudioDuringRecording { return true }
        return wavData.map(containsAudibleSpeech) == true
    }

    static func containsAudibleSpeech(_ wavData: Data) -> Bool {
        guard let dataOffset = wavDataOffset(in: wavData), wavData.count > dataOffset else {
            return false
        }

        let pcmData = wavData[dataOffset...]
        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        let samplesPerWindow = 4_410
        guard sampleCount >= samplesPerWindow else { return false }

        var audibleWindows = 0
        return pcmData.withUnsafeBytes { bytes in
            for windowStart in stride(from: 0, to: sampleCount, by: samplesPerWindow) {
                let windowEnd = min(windowStart + samplesPerWindow, sampleCount)
                guard windowEnd - windowStart >= samplesPerWindow / 2 else { continue }

                var squaredAmplitude = 0.0
                var strongSamples = 0
                for sampleIndex in windowStart..<windowEnd {
                    let byteIndex = sampleIndex * 2
                    let rawSample = UInt16(bytes[byteIndex]) | UInt16(bytes[byteIndex + 1]) << 8
                    let sample = Double(Int16(bitPattern: rawSample)) / Double(Int16.max)
                    squaredAmplitude += sample * sample
                    if abs(sample) >= 0.012 {
                        strongSamples += 1
                    }
                }

                let windowSampleCount = Double(windowEnd - windowStart)
                let rms = sqrt(squaredAmplitude / windowSampleCount)
                let strongSampleRatio = Double(strongSamples) / windowSampleCount
                if rms >= 0.006, strongSampleRatio >= 0.015 {
                    audibleWindows += 1
                    if audibleWindows >= 2 {
                        return true
                    }
                }
            }
            return false
        }
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
        data.appendUInt16LittleEndian(UInt16(recordingChannelCount))
        data.appendUInt32LittleEndian(UInt32(recordingSampleRate))
        data.appendUInt32LittleEndian(UInt32(recordingSampleRate * recordingChannelCount * recordingBitDepth / 8))
        data.appendUInt16LittleEndian(UInt16(recordingChannelCount * recordingBitDepth / 8))
        data.appendUInt16LittleEndian(UInt16(recordingBitDepth))
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
                if !self.didReachDurationLimit, audioRecorder.currentTime >= self.activeDurationLimit {
                    self.didReachDurationLimit = true
                    if UIApplication.shared.applicationState != .active {
                        let reason = self.activeDurationLimitReason
                        Task {
                            await RecordingStatusNotificationScheduler.scheduleLimit(reason)
                        }
                    }
                    self.onRecordingDurationLimitReached?(self.activeDurationLimitReason)
                    return
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
    case dailyLimitReached

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
        case .dailyLimitReached:
            "You have reached the 60-minute voice limit for today. You can type journals and letters, and recording will be available again tomorrow."
        }
    }
}

enum RecordingDurationLimitReason {
    case perRecording
    case daily

    var title: String {
        switch self {
        case .perRecording:
            "30-minute limit reached"
        case .daily:
            "Daily voice limit reached"
        }
    }

    var processingMessage: String {
        "Your recording stopped automatically. Everything captured is intact and is now being transcribed."
    }

    var notice: String {
        switch self {
        case .perRecording:
            "Recording stopped at the 30-minute limit."
        case .daily:
            "Recording stopped because you reached today's 60-minute voice limit."
        }
    }
}

enum RecordingInterruptionReason {
    case system
    case audioInputChanged

    var notice: String {
        switch self {
        case .system:
            "Recording stopped because another system audio activity interrupted the microphone. Everything captured before the interruption is being processed."
        case .audioInputChanged:
            "Recording stopped because the microphone or audio route changed. Everything captured before the change is being processed."
        }
    }
}

@MainActor
final class RecordingProcessingBackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid
    private let name: String

    init(name: String) {
        self.name = name
        begin()
    }

    func finish() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }

    private func begin() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.finish()
            }
        }
    }
}

enum RecordingStatusNotificationScheduler {
    static func scheduleLimit(_ reason: RecordingDurationLimitReason) async {
        await schedule(title: reason.title, body: reason.processingMessage)
    }

    static func scheduleInterruption(_ reason: RecordingInterruptionReason) async {
        await schedule(title: "Recording stopped", body: reason.notice)
    }

    private static func schedule(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "recording-status-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

enum VoiceUsageTracker {
    static let maximumRecordingDuration: TimeInterval = 30 * 60
    static let betaDailyDurationLimit: TimeInterval = 60 * 60

    private static let dateKey = "betaVoiceUsageDate"
    private static let durationKey = "betaVoiceUsageDuration"

    static func remainingDuration(now: Date = Date(), defaults: UserDefaults = .standard) -> TimeInterval {
        resetIfNeeded(now: now, defaults: defaults)
        return max(0, betaDailyDurationLimit - defaults.double(forKey: durationKey))
    }

    static func recordTranscription(
        duration: TimeInterval,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) throws {
        resetIfNeeded(now: now, defaults: defaults)
        let used = defaults.double(forKey: durationKey)
        guard used + duration <= betaDailyDurationLimit + 0.5 else {
            throw RecordingError.dailyLimitReached
        }
        defaults.set(used + max(0, duration), forKey: durationKey)
    }

    private static func resetIfNeeded(now: Date, defaults: UserDefaults) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now).timeIntervalSince1970
        if defaults.double(forKey: dateKey) != today {
            defaults.set(today, forKey: dateKey)
            defaults.set(0, forKey: durationKey)
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
