package io.ente.native_video_editor.core

import org.junit.Assert.assertEquals
import org.junit.Test

class VideoClipRangeUsTest {
    @Test
    fun processingNeverExtendsPastVideoTrack() {
        assertEquals(
            VideoClipRangeUs(startUs = 0L, endUs = 2_000_000L),
            resolveVideoClipRangeUs(
                videoDurationUs = 2_000_000L,
                requestedStartUs = null,
                requestedEndUs = null
            )
        )
        assertEquals(
            VideoClipRangeUs(startUs = 250_000L, endUs = 2_000_000L),
            resolveVideoClipRangeUs(
                videoDurationUs = 2_000_000L,
                requestedStartUs = 250_000L,
                requestedEndUs = 3_000_000L
            )
        )
    }
}
