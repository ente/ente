import Foundation

public enum WatchError: String, Error, Equatable, Sendable {
  case invalidData
  case wrongEnrollment
  case payloadTooLarge
  case phoneLocked
  case staleVault
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
    guard !id.isEmpty, !secret.isEmpty else { throw WatchError.invalidData }
    switch generator {
    case .totp:
      guard (1...10).contains(digits), (1...Int(Int32.max)).contains(period) else {
        throw WatchError.invalidData
      }
    case .steam:
      guard algorithm == .sha1, digits == 5, period == 30 else {
        throw WatchError.invalidData
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
    guard let code else { throw WatchError.invalidData }
    return code
  }
}

public struct Snapshot: Codable, Sendable, Equatable {
  public let entries: [Entry]
  public let hideCodes: Bool

  public init(entries: [Entry], hideCodes: Bool = false) {
    self.entries = entries
    self.hideCodes = hideCodes
  }

  public func validate() throws {
    guard Set(entries.map(\.id)).count == entries.count else {
      throw WatchError.invalidData
    }
    for entry in entries { try entry.validate() }
  }
}
