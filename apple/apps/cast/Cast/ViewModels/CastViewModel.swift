import Combine
import SwiftUI
import UIKit

@MainActor
class CastViewModel: ObservableObject {
    @Published var currentView: CurrentView = .connecting
    @Published var deviceCode: String = ""
    @Published var currentImageData: Data?
    @Published var currentVideoData: Data?
    @Published var currentFile: CastFile?
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var pairingService = RealCastPairingService()
    private let castSession: CastSession
    private var sessionID = UUID()

    let slideshowService: RealSlideshowService

    enum CurrentView {
        case pairing
        case connecting
        case slideshow
        case error
        case empty
    }

    init() {
        castSession = CastSession()
        slideshowService = RealSlideshowService()

        setupBindings()
        startCastSession()
    }

    private func setupBindings() {
        castSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)

        slideshowService.$currentImageData
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentImageData, on: self)
            .store(in: &cancellables)
        slideshowService.$currentImageData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self else { return }
                if data != nil, currentView == .connecting || currentView == .empty {
                    currentView = .slideshow
                    statusMessage = ""
                    errorMessage = nil
                }
            }
            .store(in: &cancellables)

        slideshowService.$currentVideoData
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentVideoData, on: self)
            .store(in: &cancellables)
        slideshowService.$currentVideoData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self else { return }
                if data != nil, currentView == .connecting || currentView == .empty {
                    currentView = .slideshow
                    statusMessage = ""
                    errorMessage = nil
                }
            }
            .store(in: &cancellables)

        slideshowService.$currentFile
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentFile, on: self)
            .store(in: &cancellables)

        slideshowService.$error
            .receive(on: DispatchQueue.main)
            .compactMap(\.self)
            .sink { [weak self] error in
                self?.handleSlideshowError(error)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .authenticationExpired)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAuthenticationExpired()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .slideshowRestarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSlideshowRestarted()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                ScreenSaverManager.allowScreenSaver()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.currentView == .slideshow {
                    ScreenSaverManager.preventScreenSaver()
                }
            }
            .store(in: &cancellables)
    }

    func startCastSession() {
        sessionID = UUID()
        pairingService.stopPolling()
        pairingService = RealCastPairingService()
        let sessionID = sessionID
        let pairingService = pairingService

        castSession.setState(.registering)
        deviceCode = ""
        currentView = .pairing

        Task {
            do {
                let device = try await pairingService.registerDevice()
                guard sessionID == self.sessionID else { return }

                await MainActor.run {
                    deviceCode = device.deviceCode
                    castSession.setState(.waitingForPairing(deviceCode: device.deviceCode))
                    currentView = .pairing
                    statusMessage = "Waiting for connection..."
                }

                pairingService.startPolling(
                    device: device,
                    onPayloadReceived: { [weak self] payload in
                        Task { @MainActor in
                            guard let self, sessionID == self.sessionID else { return }
                            self.handlePayloadReceived(payload)
                        }
                    },
                    onError: { [weak self] error in
                        Task { @MainActor in
                            guard let self, sessionID == self.sessionID else { return }
                            self.handleNetworkError(error)
                        }
                    },
                )

            } catch {
                guard sessionID == self.sessionID else { return }
                handleNetworkError(error)
            }
        }
    }

    func endpointChanged() {
        sessionID = UUID()
        errorMessage = nil
        Task {
            await resetSession()
            await slideshowService.clearExpiredTokenState()
            await slideshowService.clearCache()
            startCastSession()
        }
    }

    func resetSession() async {
        ScreenSaverManager.allowScreenSaver()

        currentView = .connecting
        deviceCode = ""
        currentImageData = nil
        currentVideoData = nil
        currentFile = nil
        statusMessage = ""
        errorMessage = nil

        pairingService.stopPolling()
        await slideshowService.stop()
        castSession.setState(.idle)
    }

    private func handlePayloadReceived(_ payload: CastPayload) {
        if case let .connected(existing) = castSession.state, existing == payload {
            return
        }

        castSession.setState(.connected(payload))
        currentView = .connecting
        statusMessage = ""

        let sessionID = sessionID
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard sessionID == self.sessionID else { return }

            await slideshowService.start(castPayload: payload)

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            await MainActor.run {
                guard sessionID == self.sessionID else { return }
                let hasError = slideshowService.error != nil && !slideshowService.error!.isEmpty

                if hasError {
                    handleSlideshowError(slideshowService.error!)
                } else {
                    currentView = .slideshow
                    statusMessage = ""
                }
            }
        }
    }

    func retryOperation() {
        errorMessage = nil

        switch currentView {
        case .error:
            startCastSession()
        default:
            break
        }
    }

    func nextSlide() {
        guard currentView == .slideshow else { return }

        Task {
            await slideshowService.nextSlide()
        }
    }

    func previousSlide() {
        guard currentView == .slideshow else { return }

        Task {
            await slideshowService.previousSlide()
        }
    }

    private func handleStateChange(_ state: CastSessionState) {
        switch state {
        case .idle:
            currentView = .connecting

        case .registering:
            deviceCode = ""
            currentView = .pairing

        case let .waitingForPairing(code):
            deviceCode = code
            currentView = .pairing
            statusMessage = "Waiting for connection..."

        case let .connected(payload):
            handlePayloadReceived(payload)

        case let .error(message):
            handleError(message)
        }
    }

    private func handleSlideshowError(_ error: String) {
        // Ignore stale slideshow errors while a new connection is starting.
        // Empty-state errors may belong to the new connection.
        let isEmptyStateError = error.contains("No media files") ||
            error.contains("available in this album") ||
            error.contains("available in this collection") ||
            error.contains("Empty file list")

        if currentView == .pairing || currentView == .connecting, !isEmptyStateError {
            return
        }

        if isEmptyStateError {
            currentView = .empty
            statusMessage = ""
        } else {
            handleError(error)
        }
    }

    private func handleError(_ message: String) {
        print("Cast Error: \(message)")
        currentView = .error
        errorMessage = message
        statusMessage = ""
        castSession.setState(.error(message))
    }

    private func handleNetworkError(_ error: Error) {
        handleError("An error occurred: \(error.localizedDescription)")

        let sessionID = sessionID
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                guard sessionID == self.sessionID else { return }
                startCastSession()
            }
        }
    }

    private func handleAuthenticationExpired() {
        Task {
            await resetSession()
            await slideshowService.clearExpiredTokenState()

            await MainActor.run {
                currentView = .connecting
                errorMessage = nil
                statusMessage = "Starting fresh session..."
            }

            startCastSession()
        }
    }

    private func handleSlideshowRestarted() {
        statusMessage = ""
        errorMessage = nil

        if slideshowService.currentImageData != nil || slideshowService.currentVideoData != nil {
            currentView = .slideshow
        }
    }
}
