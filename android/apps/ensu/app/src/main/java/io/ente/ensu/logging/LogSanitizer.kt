package io.ente.ensu.logging

private val emailRegex = Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
private val bearerRegex = Regex("(?i)bearer\\s+[A-Za-z0-9._-]+")

// key=value style secrets
private val keyValueSecretRegex = Regex(
    "(?i)(token|authToken|accessToken|refreshToken|authorization|password|otp|secret|secretKey|masterKey|encryptedToken|srpA|srpB|srpM1|srpM2|kek)\\s*[:=]\\s*([^\\s,;]+)"
)

// query params in URLs
private val querySecretRegex = Regex("(?i)(token|key|sig|signature|auth|session|passkey|otp)=([^&\\s]+)")

// Very long base64-ish blobs
private val longBlobRegex = Regex("[A-Za-z0-9+/=]{40,}")

internal fun sanitizeLog(input: String?): String? {
    if (input.isNullOrBlank()) return input
    var out = input

    out = bearerRegex.replace(out) { "Bearer <redacted>" }
    out = keyValueSecretRegex.replace(out) { match ->
        val key = match.groups[1]?.value ?: "secret"
        "$key=<redacted>"
    }
    out = querySecretRegex.replace(out) { match ->
        val key = match.groups[1]?.value ?: "param"
        "$key=<redacted>"
    }
    out = emailRegex.replace(out) { "<redacted-email>" }
    out = longBlobRegex.replace(out) { "<redacted-blob>" }

    return out
}
