import Foundation

struct WhatsNewEntry: Equatable {
    let title: String
    let description: String
}

enum WhatsNewContent {
    static let version = 2
    static let entries: [WhatsNewEntry] = [
        WhatsNewEntry(
            title: "Ensu Packs",
            description: "Add knowledge from wikipedia and wikibooks to get more accurate answers."
        ),
        WhatsNewEntry(
            title: "Chat with Your Notes",
            description: "Add your markdown notes folder, and chat with your notes. Ask questions or discuss the thoughts you put down."
        ),
        WhatsNewEntry(
            title: "Gemma for high RAM phones",
            description: "For phones with >8GB RAM, Gemma 4 is the new default model."
        )
    ]
}
