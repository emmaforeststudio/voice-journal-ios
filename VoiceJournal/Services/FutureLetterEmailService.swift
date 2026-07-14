import Foundation
import Security

struct FutureLetterEmailService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func requestVerification(email: String) async throws {
        let payload = EmailPayload(email: email)
        let _: VerificationRequestResponse = try await send(
            path: "v1/email-verifications/request",
            method: "POST",
            body: payload
        )
    }

    func confirmVerification(email: String, code: String) async throws {
        let payload = VerificationConfirmationPayload(email: email, code: code)
        let _: VerificationConfirmationResponse = try await send(
            path: "v1/email-verifications/confirm",
            method: "POST",
            body: payload
        )
    }

    func isVerified(email: String) async throws -> Bool {
        var components = URLComponents(
            url: try backendURL().appendingPathComponent("v1/email-verifications/status"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "email", value: email)]
        guard let url = components?.url else {
            throw FutureLetterEmailServiceError.invalidResponse
        }
        let response: VerificationStatusResponse = try await send(url: url, method: "GET", bodyData: nil)
        return response.verified
    }

    func schedule(letter: FutureLetter, email: String) async throws -> FutureLetterEmailStatus {
        let payload = SchedulePayload(
            id: letter.id.uuidString.lowercased(),
            email: email,
            title: letter.title,
            body: letter.body,
            deliveryAt: Self.iso8601Formatter.string(from: letter.deliveryDate)
        )
        let response: ScheduleResponse = try await send(
            path: "v1/future-letters",
            method: "POST",
            body: payload
        )
        return response.status
    }

    func status(letterID: UUID) async throws -> FutureLetterEmailStatusResponse {
        try await send(
            path: "v1/future-letters/\(letterID.uuidString.lowercased())",
            method: "GET",
            bodyData: nil
        )
    }

    func cancel(letterID: UUID) async throws {
        let url = try backendURL().appendingPathComponent("v1/future-letters/\(letterID.uuidString.lowercased())")
        var request = try authenticatedRequest(url: url, method: "DELETE")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FutureLetterEmailServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeError(from: data)
        }
    }

    func deleteDeviceData() async throws {
        let url = try backendURL().appendingPathComponent("v1/email-device")
        var request = try authenticatedRequest(url: url, method: "DELETE")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FutureLetterEmailServiceError.invalidResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            try FutureLetterDeviceCredentialsStore.reset()
            return
        }

        let backendError = try? JSONDecoder().decode(EmailBackendError.self, from: data)
        if httpResponse.statusCode == 401, backendError?.code == "device_not_registered" {
            try FutureLetterDeviceCredentialsStore.reset()
            return
        }
        throw decodeError(from: data)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        return try await send(path: path, method: method, bodyData: data)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?
    ) async throws -> Response {
        let url = try backendURL().appendingPathComponent(path)
        return try await send(url: url, method: method, bodyData: bodyData)
    }

    private func send<Response: Decodable>(
        url: URL,
        method: String,
        bodyData: Data?
    ) async throws -> Response {
        var request = try authenticatedRequest(url: url, method: method)
        request.timeoutInterval = 30
        request.httpBody = bodyData
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FutureLetterEmailServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeError(from: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw FutureLetterEmailServiceError.invalidResponse
        }
    }

    private func authenticatedRequest(url: URL, method: String) throws -> URLRequest {
        let credentials = try FutureLetterDeviceCredentialsStore.credentials()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.deviceID.uuidString.lowercased(), forHTTPHeaderField: "X-Flara-Device-ID")
        request.setValue("Bearer \(credentials.secret)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func backendURL() throws -> URL {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "VoiceJournalBackendURL") as? String,
            let url = URL(string: value)
        else {
            throw FutureLetterEmailServiceError.missingBackendURL
        }
        return url
    }

    private func decodeError(from data: Data) -> FutureLetterEmailServiceError {
        let error = try? JSONDecoder().decode(EmailBackendError.self, from: data)
        return .backend(code: error?.code, message: error?.error ?? "Email delivery was unavailable.")
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct FutureLetterEmailStatusResponse: Decodable {
    let status: FutureLetterEmailStatus
    let deliveredAt: String?

    var deliveredDate: Date? {
        guard let deliveredAt else { return nil }
        return FutureLetterEmailStatusResponse.iso8601Formatter.date(from: deliveredAt)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum FutureLetterEmailStatus: String, Codable {
    case scheduled
    case sending
    case retry
    case sent
    case failed
    case canceled
}

private struct EmailPayload: Encodable {
    let email: String
}

private struct VerificationConfirmationPayload: Encodable {
    let email: String
    let code: String
}

private struct SchedulePayload: Encodable {
    let id: String
    let email: String
    let title: String
    let body: String
    let deliveryAt: String
}

private struct VerificationRequestResponse: Decodable {
    let sent: Bool
}

private struct VerificationConfirmationResponse: Decodable {
    let verified: Bool
}

private struct VerificationStatusResponse: Decodable {
    let verified: Bool
}

private struct ScheduleResponse: Decodable {
    let status: FutureLetterEmailStatus
}

private struct EmailBackendError: Decodable {
    let error: String
    let code: String?
}

enum FutureLetterEmailServiceError: LocalizedError {
    case missingBackendURL
    case invalidResponse
    case credentialsUnavailable
    case backend(code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .missingBackendURL:
            "The Flara Day backend URL is not configured."
        case .invalidResponse:
            "The email service returned an invalid response."
        case .credentialsUnavailable:
            "Flara Day could not secure this device for email delivery."
        case .backend(_, let message):
            message
        }
    }
}

private struct FutureLetterDeviceCredentials: Codable {
    let deviceID: UUID
    let secret: String
}

private enum FutureLetterDeviceCredentialsStore {
    private static let service = "com.emmaforeststudio.FlaraDay.future-email"
    private static let account = "device-credentials"

    static func credentials() throws -> FutureLetterDeviceCredentials {
        if let stored = try read() {
            return stored
        }

        var randomBytes = Data(count: 32)
        let result = randomBytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw FutureLetterEmailServiceError.credentialsUnavailable
        }

        let credentials = FutureLetterDeviceCredentials(
            deviceID: UUID(),
            secret: randomBytes.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        )
        try save(credentials)
        return credentials
    }

    private static func read() throws -> FutureLetterDeviceCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw FutureLetterEmailServiceError.credentialsUnavailable
        }
        return try JSONDecoder().decode(FutureLetterDeviceCredentials.self, from: data)
    }

    private static func save(_ credentials: FutureLetterDeviceCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw FutureLetterEmailServiceError.credentialsUnavailable
        }
    }

    static func reset() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FutureLetterEmailServiceError.credentialsUnavailable
        }
    }
}
