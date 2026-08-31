import Foundation

final class ProcessLockRegistry: @unchecked Sendable {
    static let shared = ProcessLockRegistry()

    private struct Holder {
        let instanceId: String
        var origin: String
        var operation: String
        let acquiredAt: DispatchTime
    }

    private let lock = NSLock()
    private var holders: [String: Holder] = [:]

    private init() {}

    func tryAcquire(
        name: String,
        instanceId: String,
        origin: String,
        operation: String
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if var current = holders[name] {
            // A Dart hot restart can leave this plugin instance holding the lock.
            guard current.instanceId == instanceId else { return false }
            NSLog(
                "ProcessLockRegistry: healed same-instance holder of '%@' (%@/%@ -> %@/%@)",
                name, current.origin, current.operation, origin, operation
            )
            current.origin = origin
            current.operation = operation
            holders[name] = current
            return true
        }
        holders[name] = Holder(
            instanceId: instanceId,
            origin: origin,
            operation: operation,
            acquiredAt: .now()
        )
        return true
    }

    func release(name: String, instanceId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard holders[name]?.instanceId == instanceId else { return false }
        holders.removeValue(forKey: name)
        return true
    }

    func releaseAll(instanceId: String) {
        lock.lock()
        defer { lock.unlock() }
        let released = holders.filter { $0.value.instanceId == instanceId }
        if !released.isEmpty {
            let description =
                released
                .map { "\($0.key) (\($0.value.origin)/\($0.value.operation))" }
                .joined(separator: ", ")
            NSLog(
                "ProcessLockRegistry: engine detach released lock(s) still held: %@",
                description
            )
        }
        holders = holders.filter { $0.value.instanceId != instanceId }
    }

    func state(name: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard let holder = holders[name] else { return nil }
        let heldForNanos =
            DispatchTime.now().uptimeNanoseconds - holder.acquiredAt.uptimeNanoseconds
        return [
            "origin": holder.origin,
            "operation": holder.operation,
            "heldForMillis": Int64(heldForNanos / 1_000_000),
        ]
    }
}
