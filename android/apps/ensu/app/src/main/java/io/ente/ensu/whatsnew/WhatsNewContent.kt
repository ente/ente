package io.ente.ensu.whatsnew

data class WhatsNewEntry(
    val title: String,
    val description: String
)

object WhatsNewContent {
    const val VERSION: Int = 1

    val entries: List<WhatsNewEntry> = listOf(
        WhatsNewEntry(
            title = "Talk to Ensu",
            description = "On-device voice transcription is here — tap the mic and speak your prompt instead of typing. Nothing leaves your phone."
        ),
        WhatsNewEntry(
            title = "Image queries, way faster",
            description = "Under-the-hood improvements make asking Ensu about a picture feel noticeably quicker."
        ),
        WhatsNewEntry(
            title = "Faster, smoother model downloads",
            description = "Getting a new model onto your device is now dramatically quicker and more reliable."
        )
    )
}
