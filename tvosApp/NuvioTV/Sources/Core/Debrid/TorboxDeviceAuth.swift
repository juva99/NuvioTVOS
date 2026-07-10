import Foundation
import Combine

struct TorboxDeviceAuthorization {
    let deviceCode: String
    let userCode: String
    let verificationURL: String
    let friendlyVerificationURL: String
    let intervalSeconds: Int
}

enum TorboxDeviceTokenResult {
    case authorized(String)
    case pending
    case expired
    case failed(String?)
}

struct TorboxDeviceAuthService {
    private let baseURL = URL(string: "https://api.torbox.app")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func start() async throws -> TorboxDeviceAuthorization {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/api/user/auth/device/start"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "app", value: "Nuvio")]
        guard let url = components?.url else { throw DeviceAuthError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DeviceAuthError.invalidResponse
        }
        let envelope = try JSONDecoder().decode(DeviceStartEnvelope.self, from: data)
        guard envelope.success != false,
              let result = envelope.data,
              let deviceCode = result.deviceCode?.nonEmpty,
              let userCode = result.code?.nonEmpty,
              let verificationURL = result.verificationURL?.nonEmpty else {
            throw DeviceAuthError.invalidResponse
        }
        return TorboxDeviceAuthorization(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: verificationURL,
            friendlyVerificationURL: result.friendlyVerificationURL?.nonEmpty ?? verificationURL,
            intervalSeconds: max(result.interval ?? 5, 1)
        )
    }

    func redeem(deviceCode: String) async throws -> TorboxDeviceTokenResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/api/user/auth/device/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeviceTokenRequest(deviceCode: deviceCode))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return .failed(nil) }
        let envelope = try? JSONDecoder().decode(DeviceTokenEnvelope.self, from: data)
        if 200..<300 ~= http.statusCode,
           envelope?.success != false,
           let token = envelope?.data?.accessToken?.nonEmpty {
            return .authorized(token)
        }

        let message = [envelope?.error, envelope?.detail, String(data: data, encoding: .utf8)]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        if message.contains("expired") || http.statusCode == 410 { return .expired }
        if message.contains("pending")
            || message.contains("not authorized")
            || message.contains("not been used")
            || message.contains("not used yet")
            || message.contains("scan the code")
            || [404, 409, 425].contains(http.statusCode) {
            return .pending
        }
        return .failed(envelope?.detail ?? envelope?.error)
    }
}

@MainActor
final class TorboxDeviceAuthViewModel: ObservableObject {
    @Published private(set) var authorization: TorboxDeviceAuthorization?
    @Published private(set) var isStarting = false
    @Published private(set) var isPolling = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let service: TorboxDeviceAuthService
    private var task: Task<Void, Never>?

    init(service: TorboxDeviceAuthService = TorboxDeviceAuthService()) {
        self.service = service
    }

    func start(onAuthorized: @escaping @MainActor (String) -> Void) {
        task?.cancel()
        authorization = nil
        errorMessage = nil
        statusMessage = "Starting secure sign in..."
        isStarting = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let authorization = try await service.start()
                guard !Task.isCancelled else { return }
                self.authorization = authorization
                self.isStarting = false
                self.statusMessage = "Waiting for approval..."
                await self.poll(authorization, onAuthorized: onAuthorized)
            } catch is CancellationError {
                self.isStarting = false
            } catch {
                self.isStarting = false
                self.errorMessage = "Could not start TorBox sign in. Try again."
                self.statusMessage = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isStarting = false
        isPolling = false
    }

    private func poll(
        _ authorization: TorboxDeviceAuthorization,
        onAuthorized: @escaping @MainActor (String) -> Void
    ) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(authorization.intervalSeconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                isPolling = true
                let result = try await service.redeem(deviceCode: authorization.deviceCode)
                isPolling = false
                switch result {
                case .authorized(let token):
                    statusMessage = "TorBox connected."
                    onAuthorized(token)
                    return
                case .pending:
                    statusMessage = "Waiting for approval..."
                case .expired:
                    errorMessage = "This code expired. Try again."
                    statusMessage = nil
                    return
                case .failed(let message):
                    errorMessage = message?.nonEmpty ?? "TorBox sign in failed. Try again."
                    statusMessage = nil
                    return
                }
            } catch is CancellationError {
                isPolling = false
                return
            } catch {
                isPolling = false
                statusMessage = "Waiting for approval..."
            }
        }
    }
}

private enum DeviceAuthError: Error {
    case invalidResponse
}

private struct DeviceStartEnvelope: Decodable {
    let success: Bool?
    let data: DeviceStartData?
}

private struct DeviceStartData: Decodable {
    let deviceCode: String?
    let code: String?
    let verificationURL: String?
    let friendlyVerificationURL: String?
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case code
        case verificationURL = "verification_url"
        case friendlyVerificationURL = "friendly_verification_url"
        case interval
    }
}

private struct DeviceTokenRequest: Encodable {
    let deviceCode: String

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
    }
}

private struct DeviceTokenEnvelope: Decodable {
    let success: Bool?
    let data: DeviceTokenData?
    let error: String?
    let detail: String?
}

private struct DeviceTokenData: Decodable {
    let accessToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
