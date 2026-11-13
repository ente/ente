import Foundation

struct WhatsNewEntry: Equatable {
    let title: String
    let description: String
}

enum WhatsNewContent {
    static let version = 3
    static let entries: [WhatsNewEntry] = [
        WhatsNewEntry(
            title: "Keep the conversation going",
            description:
                "Ensu now keeps better track of the details that matter in longer chats, so you can ask follow-up questions with less need to repeat yourself."
        )
    ]
}
