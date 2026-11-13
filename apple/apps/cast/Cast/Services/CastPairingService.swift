import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "io.ente.cast", category: "Pairing")

@MainActor
class CastSession: ObservableObject {
    @Published var state: CastSessionState = .idle
    @Published var isActive: Bool = false

    var deviceCode: String? {
        if case let .waitingForPairing(code) = state {
            return code
        }
        return nil
    }

    var payload: CastPayload? {
        if case let .connected(payload) = state {
            return payload
        }
        return nil
    }

    func setState(_ newState: CastSessionState) {
        guard state != newState else { return }
        state = newState
        isActive = !isIdle
    }

    private var isIdle: Bool {
        if case .idle = state {
            return true
        }
        return false
    }
}

@MainActor
class RealCastPairingService {
    private let baseURL = APIEndpoint.current
    private var pollingTimer: Timer?
    private var isPolling: Bool = false
    private var isFetchingPayload: Bool = false
    private var hasDeliveredPayload: Bool = false
    private var pollingStartTime: Date?
    private let initialPollingInterval: TimeInterval = 2.0
    private let extendedPollingInterval: TimeInterval = 5.0
    private let pollingIntervalSwitchTime: TimeInterval = 60.0

    private func getCurrentPollingInterval() -> TimeInterval {
        guard let startTime = pollingStartTime else { return initialPollingInterval }
        let elapsed = Date().timeIntervalSince(startTime)
        return elapsed >= pollingIntervalSwitchTime
            ? extendedPollingInterval : initialPollingInterval
    }

    func registerDevice() async throws -> CastDevice {
        let receiver = CastReceiver()

        let url = baseURL.appendingPathComponent("cast/device-info")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = [
            "publicKey": receiver.publicKey(),
            "pqPublicKey": receiver.pqPublicKey(),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CastError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw CastError.serverError(
                httpResponse.statusCode,
                String(data: data, encoding: .utf8),
            )
        }

        let deviceResponse = try JSONDecoder().decode(DeviceRegistrationResponse.self, from: data)

        logger.info("Device registered")

        return CastDevice(
            deviceCode: deviceResponse.deviceCode,
            receiver: receiver,
        )
    }

    func startPolling(
        device: CastDevice,
        onPayloadReceived: @escaping @MainActor (CastPayload) -> Void,
        onError: @escaping @MainActor (Error) -> Void,
    ) {
        guard !hasDeliveredPayload else { return }
        guard !isPolling else { return }
        pollingTimer?.invalidate()
        isPolling = true
        pollingStartTime = Date()

        scheduleNextPoll(device: device, onPayloadReceived: onPayloadReceived, onError: onError)
    }

    private func scheduleNextPoll(
        device: CastDevice,
        onPayloadReceived: @escaping @MainActor (CastPayload) -> Void,
        onError: @escaping @MainActor (Error) -> Void,
    ) {
        guard isPolling, !hasDeliveredPayload else { return }

        let currentInterval = getCurrentPollingInterval()
        pollingTimer =
            Timer
            .scheduledTimer(withTimeInterval: currentInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    await self?.checkForPayload(
                        device: device,
                        onPayloadReceived: onPayloadReceived,
                        onError: onError,
                    )
                    // Poll again only after this request finishes.
                    self?.scheduleNextPoll(
                        device: device,
                        onPayloadReceived: onPayloadReceived,
                        onError: onError,
                    )
                }
            }
    }

    private func checkForPayload(
        device: CastDevice,
        onPayloadReceived: @escaping @MainActor (CastPayload) -> Void,
        onError: @escaping @MainActor (Error) -> Void,
    ) async {
        if hasDeliveredPayload {
            return
        }
        if isFetchingPayload {
            return
        }
        isFetchingPayload = true
        defer { isFetchingPayload = false }
        do {
            let url = baseURL.appendingPathComponent("cast/cast-data/\(device.deviceCode)")

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CastError.networkError("Invalid response")
            }

            if httpResponse.statusCode == 404 {
                // 404 means no cast payload is available yet.
                return
            }

            guard httpResponse.statusCode == 200 else {
                throw CastError.serverError(
                    httpResponse.statusCode,
                    String(data: data, encoding: .utf8),
                )
            }

            let castDataResponse = try JSONDecoder().decode(CastDataResponse.self, from: data)

            guard let encryptedData = castDataResponse.encCastData else {
                return
            }

            let payload = try device.receiver.openPayload(encryptedPayload: encryptedData)

            hasDeliveredPayload = true
            stopPolling()

            onPayloadReceived(payload)

        } catch {
            onError(error)
        }
    }

    func stopPolling() {
        guard isPolling else { return }
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPolling = false
        pollingStartTime = nil
    }
}
