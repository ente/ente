import Foundation

@available(iOS 17, macOS 14, watchOS 10, *)
struct WatchRepository {
  struct State {
    let enrollment: Enrollment?
    let snapshot: Snapshot
    let receipt: Receipt?
  }

  private let keys = PasscodeKeychain()
  private let file: SnapshotFile

  init(file: SnapshotFile) {
    self.file = file
  }

  func enrollment() throws -> Enrollment? { try keys.read()?.enrollment }

  func read() throws -> State {
    let key = try keys.read()
    let envelope = try file.read()
    guard let key else {
      if let envelope, envelope.header.kind == .retire {
        return State(
          enrollment: nil, snapshot: Snapshot(entries: []), receipt: Receipt(applied: envelope))
      }
      try file.remove()
      return State(enrollment: nil, snapshot: Snapshot(entries: []), receipt: nil)
    }
    guard let envelope else {
      return State(enrollment: try key.enrollment, snapshot: Snapshot(entries: []), receipt: nil)
    }
    let snapshot = try envelope.open(using: key)
    let receipt = Receipt(applied: envelope)
    if envelope.header.kind == .retire {
      try keys.remove()
      return State(enrollment: nil, snapshot: snapshot, receipt: receipt)
    }
    return State(enrollment: try key.enrollment, snapshot: snapshot, receipt: receipt)
  }

  func begin(suite: CipherSuite) throws -> Enrollment {
    if let enrollment = try read().enrollment { return enrollment }
    let key = try PrivateKey.generate(suite: suite)
    try file.remove()
    try keys.write(key)
    return try key.enrollment
  }

  func apply(_ data: Data) throws -> State {
    let state = try read()
    let envelope = try Envelope.decode(data)
    guard let key = try keys.read() else {
      if state.receipt == Receipt(applied: envelope) { return state }
      throw WatchError.wrongEnrollment
    }
    _ = try envelope.open(using: key)
    if let receipt = state.receipt, try !receipt.needsReplacement(with: envelope) { return state }
    try file.write(envelope)
    return try read()
  }

  func erase() throws {
    try keys.remove()
    try file.remove()
  }
}
