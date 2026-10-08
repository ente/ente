package io.ente.ensu.device

import org.junit.Assert.assertEquals
import org.junit.Test

class ModelMemoryHeadroomTest {
    @Test
    fun profileReserveRespectsPlatformThreshold() {
        assertEquals(
            1500uL,
            modelMemoryHeadroomBytes(12000, 2000, 200, optionalReserveCapBytes = 500),
        )
        assertEquals(
            0uL,
            modelMemoryHeadroomBytes(12000, 400, 200, optionalReserveCapBytes = 500),
        )
        assertEquals(
            1200uL,
            modelMemoryHeadroomBytes(12000, 2000, 800, optionalReserveCapBytes = 500),
        )
    }

    @Test
    fun optionalHeadroomPreservesSystemReserve() {
        assertEquals(100uL, modelMemoryHeadroomBytes(4000, 500, 100))
        assertEquals(0uL, modelMemoryHeadroomBytes(4000, 300, 100))
        assertEquals(100uL, modelMemoryHeadroomBytes(4000, 800, 700))
        assertEquals(3100uL, modelMemoryHeadroomBytes(4000, 3500, 100))
    }

    @Test
    fun requiredWorkPreservesPlatformThresholdWithoutTheSpeculativeReserve() {
        assertEquals(400uL, modelMemoryHeadroomBytes(4000, 500, 100, optionalWork = false))
        assertEquals(0uL, modelMemoryHeadroomBytes(4000, 90, 100, optionalWork = false))
    }
}
