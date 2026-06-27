import SwiftUI

struct LockableRootView<Content: View>: View {
    @AppStorage("faceIDLockEnabled") private var faceIDLockEnabled = false
    @AppStorage("passwordLockEnabled") private var passwordLockEnabled = false
    @AppStorage("appLockPassword") private var appLockPassword = ""
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
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("Voice Journal Locked")
                .font(.title2.bold())

            if passwordLockEnabled && !appLockPassword.isEmpty {
                NumericPasswordDots(count: passwordAttempt.count, length: 6)
            }

            if let message {
                Text(message)
                    .font(.callout)
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
                    } else {
                        Image(systemName: "faceid")
                    }
                    Text(isAuthenticatingWithFaceID ? "Checking Face ID" : "Face ID unlocks automatically")
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onAppear {
            if faceIDLockEnabled && !isUnlocked {
                Task {
                    await unlock()
                }
            }
        }
    }

    @MainActor
    private func unlock() async {
        guard faceIDLockEnabled, !isAuthenticatingWithFaceID else { return }
        isAuthenticatingWithFaceID = true
        defer { isAuthenticatingWithFaceID = false }
        let result = await AppLockAuthenticator.authenticate(reason: "Unlock Voice Journal.")
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
