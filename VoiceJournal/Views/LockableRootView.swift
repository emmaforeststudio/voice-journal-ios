import SwiftUI

struct LockableRootView<Content: View>: View {
    @AppStorage("faceIDLockEnabled") private var faceIDLockEnabled = false
    @AppStorage("passwordLockEnabled") private var passwordLockEnabled = false
    @AppStorage("appLockPassword") private var appLockPassword = ""
    @AppStorage("themeColorPreference") private var themeColorPreference = AppColorTheme.h1.rawValue
    @AppStorage("journalFontDesignPreference") private var journalFontDesignPreference = JournalFontDesignPreference.system.rawValue
    @AppStorage("journalFontPreference") private var journalFontPreference = JournalFontPreference.standard.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var isUnlocked = false
    @State private var passwordAttempt = ""
    @State private var message: String?
    @State private var isAuthenticatingWithFaceID = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            if isLockEnabled && !isUnlocked {
                lockScreen
            }
        }
        .task {
            if faceIDLockEnabled && !isUnlocked {
                await unlock()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if isLockEnabled && newPhase != .active {
                isUnlocked = false
                passwordAttempt = ""
            } else if isLockEnabled && newPhase == .active && faceIDLockEnabled && !isUnlocked {
                Task {
                    await unlock()
                }
            }
        }
        .onChange(of: faceIDLockEnabled) { _, isEnabled in
            isUnlocked = !isLockEnabled
            if !isEnabled {
                message = nil
            } else if !isUnlocked {
                Task {
                    await unlock()
                }
            }
        }
        .onChange(of: passwordLockEnabled) { _, isEnabled in
            isUnlocked = !isLockEnabled
            if !isEnabled {
                passwordAttempt = ""
                message = nil
            }
        }
        .onChange(of: appLockPassword) { _, newValue in
            if newValue.isEmpty {
                isUnlocked = !isLockEnabled
                passwordAttempt = ""
            }
        }
    }

    private var isLockEnabled: Bool {
        faceIDLockEnabled || (passwordLockEnabled && !appLockPassword.isEmpty)
    }

    private var lockScreen: some View {
        ZStack {
            AppThemeBackground()

            VStack(spacing: 24) {
                Image(lockIconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .foregroundColor(selectedTheme.primaryColor)

                Text("Flara Day Locked")
                    .font(selectedFontDesignPreference.font(.title2, weight: .bold))

                if passwordLockEnabled && !appLockPassword.isEmpty {
                    NumericPasswordDots(count: passwordAttempt.count, length: 6)
                }

                if let message {
                    Text(message)
                        .font(selectedFontDesignPreference.font(.callout))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if passwordLockEnabled && !appLockPassword.isEmpty {
                    NumericPasswordKeypad { digit in
                        guard passwordAttempt.count < 6 else { return }
                        passwordAttempt.append(digit)
                        unlockWithPasswordIfComplete()
                    } onDelete: {
                        if !passwordAttempt.isEmpty {
                            passwordAttempt.removeLast()
                        }
                        message = nil
                    }
                }

                if faceIDLockEnabled {
                    HStack(spacing: 8) {
                        if isAuthenticatingWithFaceID {
                            ProgressView()
                                .controlSize(.small)
                                .tint(selectedTheme.primaryColor)
                        } else {
                            Image("icon-face-id")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundColor(selectedTheme.primaryColor)
                        }
                        Text(isAuthenticatingWithFaceID ? "Checking Face ID" : "Face ID unlocks automatically")
                            .foregroundStyle(.secondary)
                    }
                    .font(selectedFontDesignPreference.font(.callout, weight: .semibold))
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(selectedTheme.primaryColor)
        .onAppear {
            if faceIDLockEnabled && !isUnlocked {
                Task {
                    await unlock()
                }
            }
        }
    }

    private var selectedTheme: AppColorTheme {
        AppColorTheme.value(for: themeColorPreference)
    }

    private var selectedFontDesignPreference: JournalFontDesignPreference {
        JournalFontDesignPreference.value(for: journalFontDesignPreference)
    }

    private var lockIconName: String {
        if passwordLockEnabled && !appLockPassword.isEmpty {
            "icon-password-lock"
        } else if faceIDLockEnabled {
            "icon-face-id"
        } else {
            "icon-password-lock"
        }
    }

    @MainActor
    private func unlock() async {
        guard faceIDLockEnabled, !isAuthenticatingWithFaceID else { return }
        isAuthenticatingWithFaceID = true
        defer { isAuthenticatingWithFaceID = false }
        let result = await AppLockAuthenticator.authenticate(reason: "Unlock Flara Day.")
        isUnlocked = result.isSuccess
        message = result.message
    }

    private func unlockWithPassword() {
        guard passwordLockEnabled, !appLockPassword.isEmpty else { return }

        if passwordAttempt == appLockPassword {
            isUnlocked = true
            passwordAttempt = ""
            message = nil
        } else {
            message = "Incorrect password."
            passwordAttempt = ""
        }
    }

    private func unlockWithPasswordIfComplete() {
        guard passwordAttempt.count == 6 else { return }
        unlockWithPassword()
    }
}
