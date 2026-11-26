import Foundation

public struct WatchStatus: Codable, Sendable {
  public let enrollment: Enrollment?
  let receipt: Receipt?
  let storageError: Bool?

  init(enrollment: Enrollment?, receipt: Receipt?, storageError: Bool = false) {
    self.enrollment = enrollment
    self.receipt = receipt
    self.storageError = storageError ? true : nil
  }

  public var active: Bool {
    guard let enrollment, let receipt else { return false }
    return receipt.enrollment == enrollment.id
  }

  func context() throws -> [String: Any] {
    ["version": 1, "watch": try JSONEncoder().encode(self)]
  }

  static func decode(_ context: [String: Any]) throws -> WatchStatus? {
    guard context["version"] as? Int == 1, let data = context["watch"] as? Data else { return nil }
    guard data.count <= 4096 else { throw WatchError.payloadTooLarge }
    let status = try JSONDecoder().decode(Self.self, from: data)
    if let receipt = status.receipt {
      guard receipt.revision > 0, receipt.digest.count == 32, receipt.enrollment.count == 64 else {
        throw WatchError.invalidData
      }
    }
    if let enrollment = status.enrollment, let receipt = status.receipt {
      guard receipt.enrollment == enrollment.id else { throw WatchError.wrongEnrollment }
    }
    return status
  }
}

struct PhoneContext: Sendable {
  let suites: [CipherSuite]
  let envelope: Data?

  init(_ context: [String: Any]) throws {
    guard context["version"] as? Int == 1 else { throw WatchError.invalidData }
    suites = (context["suites"] as? [String] ?? []).compactMap(CipherSuite.init(rawValue:))
    envelope = context["snapshot"] as? Data
    guard (envelope?.count ?? 0) <= Envelope.maximumBytes else { throw WatchError.payloadTooLarge }
  }

  static func context(envelope: Envelope?) -> [String: Any] {
    var context: [String: Any] = ["version": 1, "suites": CipherSuite.supported.map(\.rawValue)]
    context["snapshot"] = envelope?.data
    return context
  }
}
