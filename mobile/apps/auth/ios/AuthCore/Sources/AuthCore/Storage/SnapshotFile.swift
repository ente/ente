import Foundation

struct SnapshotFile: Sendable {
  let url: URL

  func read() throws -> Envelope? {
    do {
      return try Envelope.decode(Data(contentsOf: url))
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    }
  }

  func write(_ envelope: Envelope) throws {
    try writeDeviceFile(envelope.data, to: url)
  }

  func remove() throws {
    do { try FileManager.default.removeItem(at: url) } catch CocoaError.fileNoSuchFile {}
  }
}

func writeDeviceFile(
  _ data: Data, to url: URL, protection: Data.WritingOptions = .completeFileProtection
) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
  )
  try data.write(to: url, options: protection.union(.atomic))
  var file = url
  var values = URLResourceValues()
  values.isExcludedFromBackup = true
  try file.setResourceValues(values)
}
