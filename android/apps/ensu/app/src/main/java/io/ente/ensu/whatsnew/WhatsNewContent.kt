package io.ente.ensu.whatsnew

data class WhatsNewEntry(
    val title: String,
    val description: String,
)

object WhatsNewContent {
    const val VERSION: Int = 4

    val entries: List<WhatsNewEntry> =
        listOf(
            WhatsNewEntry(
                title = "Faster on all devices",
                description =
                    "Ensu is now way faster when it comes to responses. You no longer need to wait minutes for your answers.",
            )
        )
}
