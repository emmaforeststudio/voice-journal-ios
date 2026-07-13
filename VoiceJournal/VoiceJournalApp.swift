import SwiftData
import SwiftUI
import UIKit
import UserNotifications

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct VoiceJournalApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appNotificationDelegate
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if CommandLine.arguments.contains("--audio-self-test") {
                    AudioSelfTestView()
                } else {
                    LockableRootView {
                        MainTabView()
                    }
                }
#else
                LockableRootView {
                    MainTabView()
                }
#endif
            }
            .preferredColorScheme(AppColorTheme.value(for: themeColorPreference).colorScheme)
            .tint(AppColorTheme.value(for: themeColorPreference).primaryColor)
            .background(AppThemeBackground())
        }
        .modelContainer(for: [JournalEntry.self, FutureLetter.self])
    }
}

#if DEBUG
private struct AudioSelfTestView: View {
    @StateObject private var recorder = AudioRecorder()
    @State private var status = "Preparing microphone self-test..."

    var body: some View {
        Text(status)
            .multilineTextAlignment(.center)
            .padding()
            .task {
                do {
                    try await recorder.start()
                    status = "Recording microphone self-test..."
                    try await Task.sleep(for: .seconds(5))
                    let liveTranscript = try await OpenAIJournalService().previewTranscript(
                        from: recorder.currentRecordingURL!
                    )
                    try await Task.sleep(for: .seconds(3))
                    let heardAudio = recorder.hasDetectedAudio
                    let url = try recorder.stop()
                    let bytes = (try? Data(contentsOf: url).count) ?? 0
                    let draft = try await OpenAIJournalService().makeDraft(from: url)
                    guard !liveTranscript.isEmpty, !draft.body.isEmpty else {
                        throw RecordingError.noAudibleAudio
                    }
                    print("AUDIO_SELF_TEST heardAudio=\(heardAudio) bytes=\(bytes) live=\(liveTranscript) final=\(draft.body)")
                    status = "Self-test passed: \(draft.body)"
                    recorder.deleteRecording(at: url)
                } catch {
                    print("AUDIO_SELF_TEST failed: \(error.localizedDescription)")
                    status = "Self-test failed: \(error.localizedDescription)"
                }
            }
    }
}
#endif
