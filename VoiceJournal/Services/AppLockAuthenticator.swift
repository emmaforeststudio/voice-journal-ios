import Foundation
import LocalAuthentication

struct AuthenticationResult {
    let isSuccess: Bool
    let message: String?
}

enum AppLockAuthenticator {
    static func authenticate(reason: String) async -> AuthenticationResult {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return AuthenticationResult(
                isSuccess: false,
                message: error?.localizedDescription ?? "Device authentication is unavailable."
            )
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return AuthenticationResult(isSuccess: success, message: success ? nil : "Authentication was not completed.")
        } catch {
            return AuthenticationResult(isSuccess: false, message: error.localizedDescription)
        }
    }
}
