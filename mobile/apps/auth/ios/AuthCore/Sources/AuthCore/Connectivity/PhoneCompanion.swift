#if os(iOS)
  import Foundation
  import UIKit
  import WatchConnectivity

  @available(iOS 17, *)
  @MainActor
  public final class PhoneCompanion: NSObject, WCSessionDelegate {
    public enum Phase: String, Sendable {
      case unavailable, setup, approval, pending, synced, retiring, disabled, failed
    }

    public struct State: Equatable, Sendable {
      public let phase: Phase
      public let enrollmentID: String?
      public let requestID: String?
      public let vaultEpoch: String?
    }

    public private(set) var state = State(
      phase: .unavailable, enrollmentID: nil, requestID: nil, vaultEpoch: nil)
    public var onChange: (() -> Void)?

    private let session: WCSession
    private var repository: PhoneRepository?
    private let epoch: VaultEpoch
    private var watch: WatchStatus?

    public override init() {
      session = .default
      let directory = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
      epoch = VaultEpoch(url: directory.appendingPathComponent("watch/epoch"))
      super.init()
      if WCSession.isSupported() {
        session.delegate = self
        session.activate()
      }
    }

    public func approve(id: String) throws {
      refresh()
      try requireForeground()
      guard state.phase == .approval, let repository, let enrollment = watch?.enrollment,
        enrollment.id == id
      else {
        throw WatchError.wrongEnrollment
      }
      _ = try repository.start(enrollment, receipt: watch?.receipt)
      try send()
      refresh()
    }

    public func publish(_ snapshot: Snapshot, enrollmentID: String, vaultEpoch: String) throws {
      refresh()
      try requireForeground()
      guard try epoch.current() == vaultEpoch else { throw WatchError.staleVault }
      guard let repository, watch?.enrollment?.id == enrollmentID,
        try repository.read()?.enrollment.id == enrollmentID
      else { throw WatchError.wrongEnrollment }
      _ = try repository.publish(snapshot)
      try send()
      refresh()
    }

    public func disable(enrollmentID: String) throws {
      refresh()
      try requireForeground()
      guard let repository, let record = try repository.read(), record.enrollment.id == enrollmentID
      else {
        throw WatchError.wrongEnrollment
      }
      if record.envelope.header.kind != .retire {
        _ = try repository.publish(Snapshot(entries: []), retire: true)
      }
      try send()
      refresh()
    }

    public func clear() throws {
      _ = try epoch.advance()
      refresh()
    }

    private func requireForeground() throws {
      guard UIApplication.shared.applicationState == .active else {
        throw WatchError.phoneLocked
      }
    }

    public func refresh() {
      do {
        let currentEpoch = try epoch.current()
        guard WCSession.isSupported(), session.activationState == .activated,
          session.isPaired, session.isWatchAppInstalled,
          let currentDirectory = session.watchDirectoryURL
        else {
          repository = nil
          watch = nil
          update(.unavailable, epoch: currentEpoch)
          return
        }
        let repository = PhoneRepository(
          url: currentDirectory.appendingPathComponent("auth-state"), epoch: currentEpoch)
        self.repository = repository
        try send()
        var invalidStatus = false
        do {
          watch = try WatchStatus.decode(session.receivedApplicationContext)
          if let enrollment = watch?.enrollment { try enrollment.validate() }
          if let receipt = watch?.receipt { try repository.acknowledge(receipt) }
        } catch {
          watch = nil
          invalidStatus = true
        }
        var record = try repository.read()
        if record == nil, let watch, watch.active, let enrollment = watch.enrollment,
          let receipt = watch.receipt
        {
          record = try repository.start(enrollment, receipt: receipt, kind: .retire)
        }
        let phase: Phase
        if invalidStatus || watch?.storageError == true {
          phase = .failed
        } else if let watch, watch.enrollment == nil, watch.receipt == nil {
          phase = record?.envelope.header.kind == .retire ? .disabled : .setup
        } else if let enrollment = watch?.enrollment, record?.enrollment != enrollment {
          phase = .approval
        } else if let record, record.envelope.header.kind == .retire {
          phase = record.delivered ? .disabled : .retiring
        } else if watch?.enrollment != nil {
          phase = record?.delivered == true ? .synced : .pending
        } else {
          phase = record == nil ? .setup : .pending
        }
        try send()
        setState(
          State(
            phase: phase, enrollmentID: record?.enrollment.id, requestID: watch?.enrollment?.id,
            vaultEpoch: currentEpoch)
        )
      } catch { update(.failed, epoch: try? epoch.current()) }
    }

    private func send() throws {
      guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled
      else { return }
      let envelope = try repository?.read()?.envelope
      let context = PhoneContext.context(envelope: envelope)
      if !NSDictionary(dictionary: session.applicationContext).isEqual(to: context) {
        try session.updateApplicationContext(context)
      }
    }

    private func update(_ phase: Phase, epoch: String?) {
      setState(
        State(
          phase: phase, enrollmentID: nil, requestID: nil,
          vaultEpoch: epoch))
    }

    private func setState(_ next: State) {
      guard next != state else { return }
      state = next
      onChange?()
    }

    nonisolated public func session(
      _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
      error: (any Error)?
    ) {
      Task { @MainActor [weak self] in self?.refresh() }
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
      Task { @MainActor [weak self] in
        self?.refresh()
      }
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
      Task { @MainActor [weak self] in self?.session.activate() }
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
      Task { @MainActor [weak self] in self?.refresh() }
    }

    nonisolated public func session(
      _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
      Task { @MainActor [weak self] in self?.refresh() }
    }
  }
#endif
