package io.ente.ensu.llm

import io.ente.ensu.llm.DownloadProgress

internal data class ResolvedDownloadProgress(
    val percent: Int?,
    val status: String,
    val phase: DownloadPhase,
    val isDownloading: Boolean,
    val isFinished: Boolean
)

internal class DownloadProgressTracker(
    initialPercent: Int? = 0,
    initialStatus: String? = "Starting download..."
) {
    private var lastVisiblePercent: Int? = initialPercent
    private var lastVisibleStatus: String? = initialStatus

    fun resolve(progress: DownloadProgress): ResolvedDownloadProgress {
        val isLoading = progress.phase == DownloadPhase.Loading
        val isFinished = progress.phase == DownloadPhase.Ready
        val rawPercent = progress.percent
        val previousPercent = lastVisiblePercent
        val previousStatus = lastVisibleStatus

        val resolvedPercent = when {
            isFinished -> 100
            rawPercent == null -> previousPercent
            previousPercent == null -> rawPercent
            rawPercent >= previousPercent -> rawPercent
            else -> previousPercent
        }
        val regressed = rawPercent != null &&
            previousPercent != null &&
            rawPercent < previousPercent
        val resolvedStatus = when {
            isFinished || isLoading -> progress.status
            regressed -> previousStatus ?: progress.status
            else -> progress.status
        }

        if (!isFinished) {
            lastVisiblePercent = resolvedPercent
            lastVisibleStatus = resolvedStatus
        }

        return ResolvedDownloadProgress(
            percent = resolvedPercent,
            status = resolvedStatus,
            phase = progress.phase,
            isDownloading = progress.phase != DownloadPhase.Failed && !isFinished,
            isFinished = isFinished
        )
    }
}
