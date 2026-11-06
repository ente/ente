package io.ente.ensu.llm

import java.io.File

internal class BackgroundCpuCapacity {
    private var limit: Int? = null

    fun update(
        foreground: Boolean,
        reported: Int,
        allowedCpus: () -> Int? = ::availableBackgroundCpus,
    ): Int {
        if (foreground) {
            limit = null
            return reported
        }
        val available = (allowedCpus() ?: reported).coerceIn(1, reported)
        return minOf(limit ?: available, available).also { limit = it }
    }
}

private fun availableBackgroundCpus(): Int? = runCatching {
    File("/proc/thread-self/status").useLines { lines ->
        lines
            .firstOrNull { it.startsWith("Cpus_allowed_list:") }
            ?.substringAfter(":")
            ?.let(::parseAllowedCpuCount)
    }
}
    .getOrNull()

internal fun parseAllowedCpuCount(value: String): Int? = runCatching {
    value
        .trim()
        .split(",")
        .sumOf { part ->
            val range = part.split("-", limit = 2).map(String::toInt)
            require(range.first() >= 0 && range.last() >= range.first())
            range.last().toLong() - range.first() + 1
        }
        .takeIf { it in 1..Int.MAX_VALUE.toLong() }
        ?.toInt()
}
    .getOrNull()
