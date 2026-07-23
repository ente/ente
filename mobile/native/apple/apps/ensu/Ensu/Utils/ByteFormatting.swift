import Foundation

extension ByteCountFormatter {
    static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.fileSizeFormatter.string(fromByteCount: self)
    }
}
