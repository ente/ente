import CryptoKit
import Foundation

@available(iOS 17, macOS 14, watchOS 10, *)
struct PhoneRepository {
  struct Record: Codable, Sendable {
    let enrollment: Enrollment
    let epoch: String
    let envelope: Envelope
    let desiredDigest: Data
    var receipt: Receipt?

    var delivered: Bool {
      Receipt(applied: envelope) == receipt
    }
  }

  let url: URL
  let epoch: String

  func read() throws -> Record? {
    let data: Data
    do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile { return nil }
    let record: Record
    do { record = try JSONDecoder().decode(Record.self, from: data) } catch {
      try remove()
      return nil
    }
    guard record.epoch != epoch, record.envelope.header.kind == .snapshot else { return record }
    let cleared = try emptyRecord(after: record)
    try write(cleared)
    return cleared
  }

  func start(
    _ enrollment: Enrollment, receipt: Receipt?, kind: Envelope.Header.Kind = .snapshot
  ) throws -> Record {
    let revision = try nextRevision(
      after: receipt?.enrollment == enrollment.id ? receipt?.revision ?? 0 : 0)
    let snapshot = Snapshot(entries: [])
    let record = try Record(
      enrollment: enrollment, epoch: epoch,
      envelope: Envelope.seal(snapshot, for: enrollment, revision: revision, kind: kind),
      desiredDigest: digest(snapshot), receipt: nil
    )
    try write(record)
    return record
  }

  func publish(_ snapshot: Snapshot, retire: Bool = false) throws -> Record {
    guard let previous = try read(), previous.envelope.header.kind != .retire else {
      throw WatchError.wrongEnrollment
    }
    let desiredDigest = try digest(snapshot)
    let receiptAhead = (previous.receipt?.revision ?? 0) > previous.envelope.header.revision
    let receiptConflict =
      previous.receipt?.revision == previous.envelope.header.revision && !previous.delivered
    if !retire, desiredDigest == previous.desiredDigest, !receiptAhead, !receiptConflict {
      return previous
    }
    let revision = try nextRevision(
      after: max(previous.envelope.header.revision, previous.receipt?.revision ?? 0))
    let record = try Record(
      enrollment: previous.enrollment, epoch: epoch,
      envelope: Envelope.seal(
        snapshot, for: previous.enrollment, revision: revision, kind: retire ? .retire : .snapshot),
      desiredDigest: desiredDigest, receipt: previous.receipt
    )
    try write(record)
    return record
  }

  func acknowledge(_ receipt: Receipt) throws {
    guard var record = try read(), receipt.enrollment == record.enrollment.id else { return }
    guard receipt != record.receipt, receipt.revision >= (record.receipt?.revision ?? 0) else {
      return
    }
    record.receipt = receipt
    if !record.delivered, receipt.revision >= record.envelope.header.revision,
      record.desiredDigest == (try digest(Snapshot(entries: [])))
    {
      record = try emptyRecord(after: record)
    }
    try write(record)
  }

  func remove() throws {
    do { try FileManager.default.removeItem(at: url) } catch CocoaError.fileNoSuchFile {}
  }

  private func emptyRecord(after previous: Record) throws -> Record {
    let snapshot = Snapshot(entries: [])
    let revision = try nextRevision(
      after: max(previous.envelope.header.revision, previous.receipt?.revision ?? 0))
    return try Record(
      enrollment: previous.enrollment, epoch: epoch,
      envelope: Envelope.seal(
        snapshot, for: previous.enrollment, revision: revision, kind: previous.envelope.header.kind),
      desiredDigest: digest(snapshot), receipt: previous.receipt
    )
  }

  private func digest(_ snapshot: Snapshot) throws -> Data {
    Data(SHA256.hash(data: try Envelope.jsonData(snapshot)))
  }

  private func nextRevision(after revision: Int64) throws -> Int64 {
    guard revision < Int64.max else { throw WatchError.invalidData }
    return revision + 1
  }

  private func write(_ record: Record) throws {
    try writeDeviceFile(try JSONEncoder().encode(record), to: url)
  }
}
