import SwiftUI
import Foundation

@MainActor
class CastSession: ObservableObject {
    @Published var state: CastSessionState = .idle
    @Published var isActive: Bool = false
    
    var deviceCode: String? {
        if case .waitingForPairing(let code) = state {
            return code
        }
        return nil
    }
    
    var payload: CastPayload? {
        if case .connected(let payload) = state {
            return payload
        }
        return nil
    }
    
    func setState(_ newState: CastSessionState) {
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

class RealCastPairingService {
    private var baseURL: String { EndpointConfig.apiOrigin }
    // Bumped whenever polling starts or stops. A request already in flight
    // against the previous server finishes with a stale generation and is then
    // ignored, instead of rescheduling the shared timer or reporting an error
    // that belongs to a server the user has already moved away from.
    private var pollingGeneration: Int = 0
    private var pollingTimer: Timer?
    private var isPolling: Bool = false
    private var isFetchingPayload: Bool = false
    private var hasDeliveredPayload: Bool = false
    private var pollingStartTime: Date?
    private let initialPollingInterval: TimeInterval = 2.0
    private let extendedPollingInterval: TimeInterval = 5.0
    private let pollingIntervalSwitchTime: TimeInterval = 60.0
    private var hasLoggedIntervalSwitch: Bool = false
    
    private func getCurrentPollingInterval() -> TimeInterval {
        guard let startTime = pollingStartTime else { return initialPollingInterval }
        let elapsed = Date().timeIntervalSince(startTime)
        let newInterval = elapsed >= pollingIntervalSwitchTime ? extendedPollingInterval : initialPollingInterval
        
        if elapsed >= pollingIntervalSwitchTime && newInterval == extendedPollingInterval && !hasLoggedIntervalSwitch {
            print("Switched to extended polling interval (\(extendedPollingInterval)s) after \(Int(elapsed))s")
            hasLoggedIntervalSwitch = true
        }
        
        return newInterval
    }
    
    func registerDevice() async throws -> CastDevice {
        let receiver = CastReceiver()
        
        print("POST \(baseURL)/cast/device-info")
        
        let url = URL(string: "\(baseURL)/cast/device-info")!
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
            throw CastError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        let deviceResponse = try JSONDecoder().decode(DeviceRegistrationResponse.self, from: data)
        
        print("Device registered! Code from server: \(deviceResponse.deviceCode)")
        
        return CastDevice(
            deviceCode: deviceResponse.deviceCode,
            receiver: receiver
        )
    }
    
    func startPolling(device: CastDevice, onPayloadReceived: @escaping (CastPayload) -> Void, onError: @escaping (Error) -> Void) {
        guard !hasDeliveredPayload else { return }
        guard !isPolling else { return }
        pollingTimer?.invalidate()
        isPolling = true
        pollingStartTime = Date()
        hasLoggedIntervalSwitch = false
        pollingGeneration += 1
        
        scheduleNextPoll(generation: pollingGeneration, device: device, onPayloadReceived: onPayloadReceived, onError: onError)
    }
    
    private func scheduleNextPoll(generation: Int, device: CastDevice, onPayloadReceived: @escaping (CastPayload) -> Void, onError: @escaping (Error) -> Void) {
        guard generation == pollingGeneration, isPolling, !hasDeliveredPayload else { return }
        
        let currentInterval = getCurrentPollingInterval()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { [weak self] _ in
            Task {
                await self?.checkForPayload(generation: generation, device: device, onPayloadReceived: onPayloadReceived, onError: onError)
                // Poll again only after this request finishes.
                await MainActor.run {
                    self?.scheduleNextPoll(generation: generation, device: device, onPayloadReceived: onPayloadReceived, onError: onError)
                }
            }
        }
    }
    
    private func checkForPayload(generation: Int, device: CastDevice, onPayloadReceived: @escaping (CastPayload) -> Void, onError: @escaping (Error) -> Void) async {
        if generation != pollingGeneration { return }
        if hasDeliveredPayload { return }
        if isFetchingPayload { return }
        isFetchingPayload = true
        defer { isFetchingPayload = false }
        do {
            let url = URL(string: "\(baseURL)/cast/cast-data/\(device.deviceCode)")!
            print("GET \(url.absoluteString)")
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CastError.networkError("Invalid response")
            }
            
            if httpResponse.statusCode == 404 {
                // 404 means no cast payload is available yet.
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                throw CastError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
            }
            
            let castDataResponse = try JSONDecoder().decode(CastDataResponse.self, from: data)
            
            guard let encryptedData = castDataResponse.encCastData else {
                return
            }
            
            
            let payload = try device.receiver.openPayload(encryptedPayload: encryptedData)
            
            guard generation == pollingGeneration else { return }
            hasDeliveredPayload = true
            stopPolling()
            
            await MainActor.run {
                onPayloadReceived(payload)
            }
            
        } catch {
            print("Polling error: \(error)")
            guard generation == pollingGeneration else { return }
            await MainActor.run {
                onError(error)
            }
        }
    }
    
    func stopPolling() {
        pollingGeneration += 1
        // A request suspended against the previous server holds this flag until
        // it returns, and would make the replacement session's polls take the
        // early return instead of reaching the newly configured endpoint. Its
        // own defer clearing the flag again afterwards is harmless.
        isFetchingPayload = false
        guard isPolling else { return }
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPolling = false
        pollingStartTime = nil
    }
    
    func resetForNewSession() {
        stopPolling()
        hasDeliveredPayload = false
        hasLoggedIntervalSwitch = false
    }
}
