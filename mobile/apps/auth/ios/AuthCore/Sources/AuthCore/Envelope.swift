import Compression
import CryptoKit
import Foundation

public struct Envelope: Sendable {
  public static let maximumBytes = 48 * 1024
  public static let maxPlaintextBytes = 256 * 1024
  static let context = Data("io.ente.auth.watch.snapshot.v1".utf8)

  struct Header: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case snapshot, retire }

    let version: Int
    let enrollment: String
    let suite: CipherSuite
    let revision: Int64
    let kind: Kind
  }

  private struct Body: Codable {
    let header: Data
    let encapsulatedKey: Data
    let ciphertext: Data
  }

  let header: Header
  let encapsulatedKey: Data
  let ciphertext: Data
  let data: Data
  private let authenticatedHeader: Data

  var digest: Data { Data(SHA256.hash(data: data)) }

  // Preserve sender bytes for AAD, storage, retries and receipts across app versions.
  static func decode(_ data: Data) throws -> Envelope {
    guard data.count <= maximumBytes else { throw WatchError.payloadTooLarge }
    let body = try JSONDecoder().decode(Body.self, from: data)
    let header = try JSONDecoder().decode(Header.self, from: body.header)
    guard header.version == 1, header.revision > 0, header.enrollment.count == 64 else {
      throw WatchError.invalidData
    }
    return Envelope(
      header: header, encapsulatedKey: body.encapsulatedKey, ciphertext: body.ciphertext,
      data: data, authenticatedHeader: body.header
    )
  }

  @available(iOS 17, macOS 14, watchOS 10, *)
  static func seal(
    _ snapshot: Snapshot, for enrollment: Enrollment, revision: Int64,
    kind: Header.Kind = .snapshot
  ) throws -> Envelope {
    try snapshot.validate()
    guard kind != .retire || snapshot.entries.isEmpty else { throw WatchError.invalidData }
    let raw = try jsonData(snapshot)
    guard raw.count <= maxPlaintextBytes else { throw WatchError.payloadTooLarge }
    let compressed = try runCompression(COMPRESSION_STREAM_ENCODE, input: raw)
    let header = Header(
      version: 1, enrollment: enrollment.id, suite: enrollment.suite, revision: revision, kind: kind
    )
    let headerData = try jsonData(header)
    var sender = try enrollment.sender(info: context)
    let ciphertext = try sender.seal(compressed, authenticating: headerData)
    return try decode(
      jsonData(
        Body(header: headerData, encapsulatedKey: sender.encapsulatedKey, ciphertext: ciphertext)))
  }

  @available(iOS 17, macOS 14, watchOS 10, *)
  func open(using privateKey: PrivateKey) throws -> Snapshot {
    var recipient = try privateKey.recipient(for: self)
    let raw = try recipient.open(ciphertext, authenticating: authenticatedHeader)
    let plaintext = try Self.runCompression(
      COMPRESSION_STREAM_DECODE, input: raw, maxOutputBytes: Self.maxPlaintextBytes)
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: plaintext)
    try snapshot.validate()
    guard header.kind != .retire || snapshot.entries.isEmpty else {
      throw WatchError.invalidData
    }
    return snapshot
  }

  private static func runCompression(
    _ operation: compression_stream_operation,
    input: Data,
    maxOutputBytes: Int? = nil
  ) throws -> Data {
    if input.isEmpty { return Data() }
    let dummy = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    defer { dummy.deallocate() }
    var stream = compression_stream(
      dst_ptr: dummy, dst_size: 0, src_ptr: UnsafePointer(dummy), src_size: 0, state: nil
    )
    guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR
    else {
      throw WatchError.invalidData
    }
    defer { compression_stream_destroy(&stream) }

    var output = Data()
    let chunkSize = 4096
    var buffer = [UInt8](repeating: 0, count: chunkSize)
    try input.withUnsafeBytes { srcRaw in
      guard let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return }
      stream.src_ptr = srcBase
      stream.src_size = srcRaw.count
      while true {
        let status: compression_status = buffer.withUnsafeMutableBytes { dstRaw in
          stream.dst_ptr = dstRaw.bindMemory(to: UInt8.self).baseAddress!
          stream.dst_size = chunkSize
          let flags =
            (operation == COMPRESSION_STREAM_ENCODE || stream.src_size == 0)
            ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            : 0
          return compression_stream_process(&stream, flags)
        }
        let written = chunkSize - stream.dst_size
        if let maxOutputBytes, output.count + written > maxOutputBytes {
          throw WatchError.payloadTooLarge
        }
        if written > 0 {
          output.append(contentsOf: buffer[0..<written])
        }
        if status == COMPRESSION_STATUS_END {
          break
        }
        if status == COMPRESSION_STATUS_ERROR || (written == 0 && stream.src_size == 0) {
          throw WatchError.invalidData
        }
      }
    }
    return output
  }

  static func jsonData(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }
}

extension Envelope: Codable {
  public init(from decoder: any Decoder) throws {
    self = try Self.decode(decoder.singleValueContainer().decode(Data.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(data)
  }
}

struct Receipt: Codable, Equatable, Sendable {
  let enrollment: String
  let revision: Int64
  let digest: Data

  init(applied envelope: Envelope) {
    enrollment = envelope.header.enrollment
    revision = envelope.header.revision
    digest = envelope.digest
  }

  func needsReplacement(with envelope: Envelope) throws -> Bool {
    guard enrollment == envelope.header.enrollment else { throw WatchError.wrongEnrollment }
    if envelope.header.revision < revision { return false }
    if envelope.header.revision == revision {
      guard digest == envelope.digest else { throw WatchError.invalidData }
      return false
    }
    return true
  }
}
