import Foundation

struct WhatsNewEntry: Equatable {
    let title: String
    let description: String
}

enum WhatsNewContent {
    static let version = 1
    static let entries: [WhatsNewEntry] = [
        WhatsNewEntry(
            title: "Talk to Ensu",
            description: "On-device voice transcription is here — tap the mic and speak your prompt instead of typing. Nothing leaves your phone."
        ),
        WhatsNewEntry(
            title: "Image queries, way faster",
            description: "Under-the-hood improvements make asking Ensu about a picture feel noticeably quicker."
        ),
        WhatsNewEntry(
            title: "Faster, smoother model downloads",
            description: "Getting a new model onto your device is now dramatically quicker and more reliable."
        )
    ]
}
