import Foundation

struct MlProcessLockState: Equatable {
    let token: String
    let pluginInstanceID: String
    let origin: String
    let operation: String
    let acquiredAtUptimeNanoseconds: UInt64
}

struct MlProcessLockAcquireResult {
    let acquired: Bool
    let holder: MlProcessLockState
}

final class MlProcessLockRegistry: @unchecked Sendable {
    static let shared = MlProcessLockRegistry()

    private let lock = NSLock()
    private var holder: MlProcessLockState?

    func tryAcquire(
        pluginInstanceID: String,
        token: String,
        origin: String,
        operation: String,
        acquiredAtUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> MlProcessLockAcquireResult {
        lock.lock()
        defer { lock.unlock() }

        if let holder {
            return MlProcessLockAcquireResult(
                acquired: holder.pluginInstanceID == pluginInstanceID && holder.token == token,
                holder: holder
            )
        }
        let acquired = MlProcessLockState(
            token: token,
            pluginInstanceID: pluginInstanceID,
            origin: origin,
            operation: operation,
            acquiredAtUptimeNanoseconds: acquiredAtUptimeNanoseconds
        )
        holder = acquired
        return MlProcessLockAcquireResult(acquired: true, holder: acquired)
    }

    func release(pluginInstanceID: String, token: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard holder?.pluginInstanceID == pluginInstanceID, holder?.token == token else {
            return false
        }
        holder = nil
        return true
    }

    func reset(for pluginInstanceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard holder?.pluginInstanceID == pluginInstanceID else {
            return false
        }
        holder = nil
        return true
    }

    func state() -> MlProcessLockState? {
        lock.lock()
        defer { lock.unlock() }
        return holder
    }
}
