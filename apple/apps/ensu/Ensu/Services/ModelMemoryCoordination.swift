import Foundation

struct ModelMemoryPressureState {
    static let cooldown: TimeInterval = 30
    private var cleanupPending = false
    private var retryAfter: TimeInterval = 0

    mutating func recordPressure(now: TimeInterval) {
        cleanupPending = true
        retryAfter = now + Self.cooldown
    }

    func suppressesOptionalWork(now: TimeInterval) -> Bool {
        cleanupPending || now < retryAfter
    }

    func remainingCooldown(now: TimeInterval) -> TimeInterval {
        max(0, retryAfter - now)
    }

    func requiresCleanup(appForeground: Bool, now: TimeInterval) -> Bool {
        !appForeground || suppressesOptionalWork(now: now)
    }

    mutating func didCleanUp() {
        cleanupPending = false
    }
}

enum ChatWarmupResult {
    case ready
    case skipped
    case retryAfter(TimeInterval)
}

func retryChatWarmup(
    isolation: isolated (any Actor)? = #isolation,
    isEligible: () -> Bool,
    wait: (TimeInterval) async throws -> Void = {
        try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    },
    operation: () async throws -> ChatWarmupResult
) async throws -> Bool {
    while true {
        try Task.checkCancellation()
        guard isEligible() else { return false }
        let result = try await operation()
        try Task.checkCancellation()
        switch result {
        case .ready:
            return true
        case .skipped:
            return false
        case .retryAfter(let delay):
            guard delay > 0 else { return false }
            try await wait(delay)
        }
    }
}

actor AsyncSerialGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(
        isolation: isolated (any Actor)? = #isolation,
        onEnter: () async -> Void = {},
        onExit: () async -> Void = {},
        _ operation: () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            try Task.checkCancellation()
            await onEnter()
            try Task.checkCancellation()
            let result = try await operation()
            await onExit()
            await release()
            return result
        } catch {
            await onExit()
            await release()
            throw error
        }
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}
