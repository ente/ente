import Darwin
import Foundation

/// Seed bytes for HMAC. `deinit` wipes the allocation with `memset_s` so the wipe cannot be optimized out.
internal final class SecretBuffer: @unchecked Sendable {
    private let pointer: UnsafeMutableRawPointer
    private let allocationCount: Int
    internal let count: Int

    internal init(bytes: [UInt8]) {
        let allocationCount = max(bytes.count, 1)
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: allocationCount,
            alignment: MemoryLayout<UInt8>.alignment
        )
        if bytes.isEmpty {
            memset(pointer, 0, allocationCount)
        } else {
            bytes.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    pointer.copyMemory(from: base, byteCount: raw.count)
                }
            }
        }
        self.pointer = pointer
        self.allocationCount = allocationCount
        self.count = bytes.count
    }

    internal convenience init(data: Data) {
        var copy = [UInt8](data)
        self.init(bytes: copy)
        Self.wipe(&copy)
    }

    deinit {
        Self.wipe(pointer, allocationCount)
        pointer.deallocate()
    }

    internal func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try body(UnsafeRawBufferPointer(start: pointer, count: count))
    }

    internal static func wipe(_ bytes: inout [UInt8]) {
        guard !bytes.isEmpty else { return }
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            wipe(base, raw.count)
        }
    }

    @inline(never)
    private static func wipe(_ pointer: UnsafeMutableRawPointer, _ count: Int) {
        _ = memset_s(pointer, count, 0, count)
    }
}
