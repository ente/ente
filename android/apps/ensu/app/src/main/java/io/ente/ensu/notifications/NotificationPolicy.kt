package io.ente.ensu.notifications

internal const val PERMISSION_INTERVAL_MS = 3L * 24 * 60 * 60 * 1000

internal fun canEducate(
    enabled: Boolean,
    finished: Boolean,
    count: Int,
    lastShown: Long?,
    now: Long,
): Boolean =
    !enabled &&
        !finished &&
        count < 3 &&
        (lastShown == null || now - lastShown >= PERMISSION_INTERVAL_MS)

internal fun responsePreview(text: String): String =
    text
        .replace(Regex("!\\[([^]]*)]\\([^)]*\\)"), "$1")
        .replace(Regex("\\[([^]]+)]\\([^)]*\\)"), "$1")
        .replace(Regex("(?m)^```[^\\n]*$"), "")
        .replace(Regex("(?m)^\\s{0,3}(#{1,6} |>|[-*+] )"), "")
        .replace("**", "")
        .replace("__", "")
        .replace("`", "")
        .replace("~~", "")
        .replace(Regex("(?<![\\w])([*_])([^\\n]+?)\\1(?![\\w])"), "$2")
        .trim()
        .take(4000)

internal fun responseNotificationTitle(query: String): String {
    val text = query.replace(Regex("\\s+"), " ").trim()
    if (text.isEmpty()) return "Ensu"
    val characters = java.util.regex.Pattern.compile("\\X").matcher(text)
    var end = 0
    repeat(30) {
        if (!characters.find()) return text
        end = characters.end()
    }
    return text.substring(0, end) + if (characters.find()) "…" else ""
}

internal data class ResponseNotificationAttempt(
    val id: Long,
    val session: String,
    val parent: String,
    val query: String,
)

internal class ResponseNotificationLifecycle {
    var current: ResponseNotificationAttempt? = null
        private set

    private var resolved = false

    fun begin(attempt: ResponseNotificationAttempt) {
        current = attempt
        resolved = false
    }

    fun resolve(id: Long): ResponseNotificationAttempt? {
        val attempt = current ?: return null
        if (attempt.id != id || resolved) return null
        resolved = true
        return attempt
    }

    fun clear(id: Long): Boolean {
        if (current?.id != id) return false
        current = null
        return true
    }
}

internal class NotificationPermissionRequestState(denialObserved: Boolean = false) {
    var denialObserved = denialObserved
        private set

    fun observeRationale(shouldShowRationale: Boolean) {
        if (shouldShowRationale) denialObserved = true
    }

    fun canRequest(shouldShowRationale: Boolean): Boolean = !denialObserved || shouldShowRationale
}
