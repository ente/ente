import Foundation

@MainActor
protocol ModelMaintenance: AnyObject {
    func suspendMaintenance() -> ModelUseScope
    func awaitMaintenance() async
}

extension ModelMaintenance {
    func withMaintenanceSuspended<T>(_ body: () async throws -> T) async throws -> T {
        let token = suspendMaintenance()
        defer { token.close() }
        await awaitMaintenance()
        try Task.checkCancellation()
        return try await body()
    }
}

final class ModelUseScope: @unchecked Sendable {
    private let lock = NSLock()
    private var release: (@Sendable () -> Void)?
    init(_ release: @escaping @Sendable () -> Void) { self.release = release }
    func close() {
        lock.lock()
        let action = release
        release = nil
        lock.unlock()
        action?()
    }
    deinit { close() }
}
