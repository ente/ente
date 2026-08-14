import Foundation

struct PendingWhatsNew: Identifiable {
    let version: Int
    let entries: [WhatsNewEntry]

    var id: Int { version }
}

final class WhatsNewService {
    static let shared = WhatsNewService()

    private let defaults: UserDefaults
    private let seenVersionKey = "ensu.whatsNew.seenVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pendingWhatsNew() -> PendingWhatsNew? {
        if defaults.object(forKey: seenVersionKey) == nil {
            markSeen()
            return nil
        }

        let seenVersion = defaults.integer(forKey: seenVersionKey)
        if seenVersion >= WhatsNewContent.version {
            return nil
        }

        if WhatsNewContent.entries.isEmpty {
            markSeen()
            return nil
        }

        return PendingWhatsNew(
            version: WhatsNewContent.version,
            entries: WhatsNewContent.entries
        )
    }

    func markSeen() {
        defaults.set(WhatsNewContent.version, forKey: seenVersionKey)
    }
}
