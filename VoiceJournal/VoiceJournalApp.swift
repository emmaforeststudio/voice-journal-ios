import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class NotificationNavigationCoordinator: ObservableObject {
    static let shared = NotificationNavigationCoordinator()

    @Published private(set) var futureLetterID: UUID?

    func openFutureLetter(id: UUID) {
        futureLetterID = id
    }

    func consumeFutureLetter(id: UUID) {
        guard futureLetterID == id else { return }
        futureLetterID = nil
    }
}

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
        if let rawLetterID = response.notification.request.content.userInfo["futureLetterID"] as? String,
           let letterID = UUID(uuidString: rawLetterID) {
            Task { @MainActor in
                NotificationNavigationCoordinator.shared.openFutureLetter(id: letterID)
            }
        }
#if DEBUG
        UserDefaults.standard.set(
            response.notification.request.identifier,
            forKey: "notificationDiagnosticLastOpenedIdentifier"
        )
#endif
        completionHandler()
    }
}

@main
struct VoiceJournalApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appNotificationDelegate
    @StateObject private var notificationNavigationCoordinator = NotificationNavigationCoordinator.shared
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if CommandLine.arguments.contains("--notification-inspect") {
                    NotificationInspectionView()
                } else if CommandLine.arguments.contains("--notification-self-test") {
                    NotificationSelfTestView()
                } else if CommandLine.arguments.contains("--audio-self-test") {
                    AudioSelfTestView()
                } else {
                    FutureLetterNotificationSyncView {
                        LockableRootView {
                            MainTabView()
                        }
                    }
                }
#else
                FutureLetterNotificationSyncView {
                    LockableRootView {
                        MainTabView()
                    }
                }
#endif
            }
            .environmentObject(notificationNavigationCoordinator)
            .preferredColorScheme(AppColorTheme.value(for: themeColorPreference).colorScheme)
            .tint(AppColorTheme.value(for: themeColorPreference).primaryColor)
            .background(AppThemeBackground())
        }
        .modelContainer(for: [JournalEntry.self, FutureLetter.self])
    }
}

private struct FutureLetterNotificationSyncView<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var letters: [FutureLetter]
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                if await FutureLetterNotificationScheduler.synchronize(letters: letters) {
                    try? modelContext.save()
                }
            }
    }
}

#if DEBUG
private struct NotificationInspectionView: View {
    @Query(sort: \FutureLetter.deliveryDate, order: .forward) private var letters: [FutureLetter]
    @State private var status = "Inspecting delivered notifications..."

    var body: some View {
        Text(status)
            .multilineTextAlignment(.center)
            .padding(28)
            .task {
                let center = UNUserNotificationCenter.current()
                let pending = await center.pendingNotificationRequests()
                let delivered = await center.deliveredNotifications()
                let settings = await center.notificationSettings()
                let formatter = ISO8601DateFormatter()
                let pendingIDs = pending.map { request in
                    let nextDate: Date?
                    if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                        nextDate = trigger.nextTriggerDate()
                    } else if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                        nextDate = trigger.nextTriggerDate()
                    } else {
                        nextDate = nil
                    }
                    let date = nextDate.map(formatter.string(from:)) ?? "none"
                    return "\(request.identifier)@\(date)"
                }.joined(separator: ",")
                let deliveredIDs = delivered.map(\.request.identifier).joined(separator: ",")
                let lastOpenedID = UserDefaults.standard.string(forKey: "notificationDiagnosticLastOpenedIdentifier") ?? "none"
                let letterDates = letters.map { letter in
                    "\(letter.id.uuidString)@\(formatter.string(from: letter.deliveryDate))#\(letter.notificationIdentifier ?? "none")"
                }.joined(separator: ",")
                let settingsDescription = "authorization=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) center=\(settings.notificationCenterSetting.rawValue) lock=\(settings.lockScreenSetting.rawValue) alertStyle=\(settings.alertStyle.rawValue) sound=\(settings.soundSetting.rawValue) summary=\(settings.scheduledDeliverySetting.rawValue)"
                print("NOTIFICATION_DIAGNOSTIC inspection settings=[\(settingsDescription)] pending=[\(pendingIDs)] delivered=[\(deliveredIDs)] lastOpened=\(lastOpenedID) letters=[\(letterDates)] now=\(formatter.string(from: Date()))")
                status = "Pending: \(pending.count)\nDelivered: \(delivered.count)"
            }
    }
}

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
            let settings = await center.notificationSettings()
            let settingsDescription = "authorization=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) center=\(settings.notificationCenterSetting.rawValue) lock=\(settings.lockScreenSetting.rawValue) alertStyle=\(settings.alertStyle.rawValue) sound=\(settings.soundSetting.rawValue) summary=\(settings.scheduledDeliverySetting.rawValue) timeSensitive=\(settings.timeSensitiveSetting.rawValue)"
            print("NOTIFICATION_DIAGNOSTIC settings \(settingsDescription)")

            let letter = FutureLetter(
                title: "Test received - please do not tap",
                body: "This verifies the same notification path used by Future Letters.",
                deliveryDate: Date().addingTimeInterval(180),
                deliveryMethod: .inAppNotification
            )
            let identifier = try await FutureLetterNotificationScheduler.schedule(letter: letter)
            let waitInterval = max(8, letter.deliveryDate.timeIntervalSinceNow + 5)

            let pendingBeforeDelivery = await center.pendingNotificationRequests()
            guard pendingBeforeDelivery.contains(where: { $0.identifier == identifier }) else {
                status = "iOS did not register the test notification."
                print("NOTIFICATION_DIAGNOSTIC registration failed")
                return
            }

            status = "iOS accepted the Future Letter notification. It should appear at \(letter.deliveryDate.formatted(date: .omitted, time: .shortened))."
            print("NOTIFICATION_DIAGNOSTIC accepted id=\(identifier) date=\(letter.deliveryDate)")
            try await Task.sleep(for: .seconds(waitInterval))

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
