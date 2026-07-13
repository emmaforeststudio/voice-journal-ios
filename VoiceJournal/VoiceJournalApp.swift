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
        print("NOTIFICATION_DIAGNOSTIC foreground delivery id=\(notification.request.identifier)")
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("NOTIFICATION_DIAGNOSTIC opened id=\(response.notification.request.identifier)")
        completionHandler()
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
                if CommandLine.arguments.contains("--notification-self-test") {
                    NotificationSelfTestView()
                } else if CommandLine.arguments.contains("--audio-self-test") {
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
private struct NotificationSelfTestView: View {
    @State private var status = "Preparing notification self-test..."

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bell.badge")
                .font(.system(size: 44))
            Text("Notification Test")
                .font(.title2.bold())
            Text(status)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .task {
            await runTest()
        }
    }

    private func runTest() async {
        let center = UNUserNotificationCenter.current()

        do {
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                guard granted else {
                    status = "Permission was not granted."
                    return
                }
                settings = await center.notificationSettings()
            }

            let settingsDescription = "authorization=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) sound=\(settings.soundSetting.rawValue) summary=\(settings.scheduledDeliverySetting.rawValue) timeSensitive=\(settings.timeSensitiveSetting.rawValue)"
            print("NOTIFICATION_DIAGNOSTIC settings \(settingsDescription)")

            guard settings.authorizationStatus == .authorized else {
                status = "Notification authorization is not active. \(settingsDescription)"
                return
            }

            let identifier = "notification-self-test-\(UUID().uuidString)"
            let content = UNMutableNotificationContent()
            content.title = "Flara Day Test"
            content.body = "Local notifications are working."
            content.sound = .default
            content.interruptionLevel = .active

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
            )
            try await center.add(request)

            let pendingBeforeDelivery = await center.pendingNotificationRequests()
            guard pendingBeforeDelivery.contains(where: { $0.identifier == identifier }) else {
                status = "iOS did not register the test notification."
                print("NOTIFICATION_DIAGNOSTIC registration failed")
                return
            }

            status = "iOS accepted the notification. It should appear in 10 seconds."
            print("NOTIFICATION_DIAGNOSTIC accepted id=\(identifier)")
            try await Task.sleep(for: .seconds(14))

            let pendingAfterDelivery = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            if delivered.contains(where: { $0.request.identifier == identifier }) {
                status = "Passed: iOS delivered the notification."
                print("NOTIFICATION_DIAGNOSTIC delivered id=\(identifier)")
            } else if pendingAfterDelivery.contains(where: { $0.identifier == identifier }) {
                status = "iOS accepted the notification but has not delivered it yet."
                print("NOTIFICATION_DIAGNOSTIC still-pending id=\(identifier)")
            } else {
                status = "iOS processed the notification, but it is not in Notification Center. Check Focus and Flara Day notification settings."
                print("NOTIFICATION_DIAGNOSTIC processed-not-visible id=\(identifier)")
            }
        } catch {
            status = "Test failed: \(error.localizedDescription)"
            print("NOTIFICATION_DIAGNOSTIC error=\(error.localizedDescription)")
        }
    }
}

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
