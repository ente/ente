import Foundation

struct ChatSourceSelection: Sendable {
    var selectedPackIDs: Set<String> = []
    var selectedCollectionIDs: Set<String> = []

    func includesPack(_ id: String) -> Bool { selectedPackIDs.contains(id) }
    func includesCollection(_ id: String) -> Bool { selectedCollectionIDs.contains(id) }
}
