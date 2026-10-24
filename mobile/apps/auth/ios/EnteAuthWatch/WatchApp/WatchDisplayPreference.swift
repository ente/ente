import Foundation
import WatchKit

/// Watch-local display flags. These keys store booleans only — never a seed or a code.
enum WatchDisplayPreference {
    static let shieldedModeKey = "ente.auth.watch.shieldedMode"
    static let rolloverHapticKey = "ente.auth.watch.rolloverHaptic"
}

/// Decides whether a rollover haptic should fire. Remembers period indexes, never codes.
/// The first observation of a period only records the index. A later index change fires
/// once, and two tokens that share the same unix boundary share that one pulse.
struct RolloverHapticMemory {
    private var lastPeriodIndex: [Int: Int] = [:]
    private var lastPlayedBoundary: Int?

    mutating func consume(period: Int, periodIndex: Int, enabled: Bool) -> Bool {
        guard period > 0 else { return false }
        let previous = lastPeriodIndex[period]
        lastPeriodIndex[period] = periodIndex
        guard enabled, let previous, previous != periodIndex else { return false }
        let boundary = periodIndex * period
        guard lastPlayedBoundary != boundary else { return false }
        lastPlayedBoundary = boundary
        return true
    }
}

/// One `directionDown` haptic per period boundary, and at most one if several
/// tokens roll in the same second.
@MainActor
final class RolloverHapticGate {
    static let shared = RolloverHapticGate()

    private var memory = RolloverHapticMemory()

    private init() {}

    func note(period: Int, periodIndex: Int, enabled: Bool) {
        guard memory.consume(period: period, periodIndex: periodIndex, enabled: enabled) else { return }
        WKInterfaceDevice.current().play(.directionDown)
    }
}
