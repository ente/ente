import Foundation

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
