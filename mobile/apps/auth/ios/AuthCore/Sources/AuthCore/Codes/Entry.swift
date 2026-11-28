import Foundation

public enum CodeError: Error {
  case invalidData
}

public struct Entry: Codable, Identifiable, Sendable, Equatable {
  public enum Generator: String, Codable, Sendable {
    case totp, steam
  }

  public let id: String
  public let issuer: String
  public let account: String
  public let secret: Data
  public let generator: Generator
  public let algorithm: OTP.Algorithm
  public let digits: Int
  public let period: Int
  public let pinned: Bool
  public let tags: [String]

  public func validate() throws {
    guard !id.isEmpty, !secret.isEmpty else { throw CodeError.invalidData }
    switch generator {
    case .totp:
      guard (1...10).contains(digits), (1...Int(Int32.max)).contains(period) else {
        throw CodeError.invalidData
      }
    case .steam:
      guard algorithm == .sha1, digits == 5, period == 30 else {
        throw CodeError.invalidData
      }
    }
  }

  public func code(at date: Date) throws -> String {
    let code =
      switch generator {
      case .totp:
        OTP.totp(secret: secret, algorithm: algorithm, digits: digits, period: period, at: date)
      case .steam:
        OTP.steam(secret: secret, at: date)
      }
    guard let code else { throw CodeError.invalidData }
    return code
  }
}

public struct Snapshot: Codable, Sendable, Equatable {
  public let entries: [Entry]

  public init(entries: [Entry]) {
    self.entries = entries
  }

  public func validate() throws {
    guard Set(entries.map(\.id)).count == entries.count else {
      throw CodeError.invalidData
    }
    for entry in entries { try entry.validate() }
  }
}
