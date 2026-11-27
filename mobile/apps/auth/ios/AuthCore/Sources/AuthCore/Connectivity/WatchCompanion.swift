#if os(watchOS)
  import Combine
  import Foundation
  import WatchConnectivity

  @MainActor
  public final class WatchCompanion: NSObject, ObservableObject, WCSessionDelegate {
    public enum Issue: Equatable { case passcodeRequired, unlockWatch, syncFailed }

    @Published public private(set) var entries: [Entry] = []
    @Published public private(set) var hideCodes = false
    @Published public private(set) var status = WatchStatus(enrollment: nil, receipt: nil)
    @Published public private(set) var issue: Issue?
    @Published public private(set) var canEnroll = false

    private let session: WCSession
    private let repository: WatchRepository
    private var visible = false
    private var phone: PhoneContext?

    public override init() {
      session = .default
      let directory = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
      let file = SnapshotFile(url: directory.appendingPathComponent("watch/snapshot"))
      repository = WatchRepository(file: file)
      super.init()
      session.delegate = self
      session.activate()
    }

    public func setVisible(_ visible: Bool) {
      self.visible = visible
      if visible {
        reload()
      } else {
        entries = []
        hideCodes = false
      }
    }

    public func enroll() {
      guard visible,
        let suite = CipherSuite.supported.first(where: { phone?.suites.contains($0) == true })
      else { return }
      do {
        _ = try repository.begin(suite: suite)
        issue = nil
        reload()
      } catch is KeychainError { issue = .passcodeRequired } catch { issue = .syncFailed }
    }

    public func erase() {
      entries = []
      hideCodes = false
      do {
        try repository.erase()
        status = WatchStatus(enrollment: nil, receipt: nil)
        issue = nil
        try sendStatus()
      } catch { issue = .syncFailed }
    }

    private func reload() {
      do {
        let initial = try repository.read()
        let applied = applyIncomingContext(to: initial)
        var syncFailed = applied.syncFailed
        let state = applied.state
        canEnroll = CipherSuite.supported.contains { phone?.suites.contains($0) == true }
        entries = visible ? state.snapshot.entries : []
        hideCodes = visible && state.snapshot.hideCodes
        status = WatchStatus(enrollment: state.enrollment, receipt: state.receipt)
        do { try sendStatus() } catch { syncFailed = true }
        issue = syncFailed ? .syncFailed : nil
        requestPhoneContext()
      } catch is KeychainError {
        entries = []
        hideCodes = false
        issue = .unlockWatch
      } catch {
        entries = []
        hideCodes = false
        issue = .syncFailed
        status = WatchStatus(
          enrollment: try? repository.enrollment(), receipt: nil, storageError: true)
        try? sendStatus()
      }
    }

    private func applyIncomingContext(to current: WatchRepository.State) -> (
      state: WatchRepository.State, syncFailed: Bool
    ) {
      var next = current
      var syncFailed = false
      do {
        if !session.receivedApplicationContext.isEmpty {
          phone = try PhoneContext(session.receivedApplicationContext)
        }
        if let data = phone?.envelope { next = try repository.apply(data) }
      } catch WatchError.wrongEnrollment {
      } catch {
        syncFailed = true
      }
      return (next, syncFailed)
    }

    private func sendStatus() throws {
      guard session.activationState == .activated else { return }
      let context = try status.context()
      if !NSDictionary(dictionary: session.applicationContext).isEqual(to: context) {
        try session.updateApplicationContext(context)
      }
    }

    private func requestPhoneContext() {
      guard phone == nil, session.activationState == .activated, session.isReachable else { return }
      session.sendMessage(
        ["version": 1],
        replyHandler: { @Sendable reply in
          guard let phone = try? PhoneContext(reply) else { return }
          Task { @MainActor [weak self] in
            guard let self, self.phone == nil else { return }
            self.phone = phone
            self.reload()
          }
        }, errorHandler: nil)
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
      Task { @MainActor [weak self] in self?.requestPhoneContext() }
    }

    nonisolated public func session(
      _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
      error: (any Error)?
    ) {
      Task { @MainActor [weak self] in self?.reload() }
    }

    nonisolated public func session(
      _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
      Task { @MainActor [weak self] in self?.reload() }
    }
  }
#endif
