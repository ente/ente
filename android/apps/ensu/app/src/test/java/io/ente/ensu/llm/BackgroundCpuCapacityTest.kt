package io.ente.ensu.llm

import org.junit.Assert.assertEquals
import org.junit.Test

class BackgroundCpuCapacityTest {
    @Test
    fun cpuListsRespectBackgroundLimitsAndResetOnForeground() {
        val capacity = BackgroundCpuCapacity()
        fun background(cpus: String) = capacity.update(false, 7) { parseAllowedCpuCount(cpus) }

        assertEquals(6, background("0-2,4,6-7"))
        assertEquals(3, background("0-2"))
        assertEquals(3, background(" 0-7\n"))
        assertEquals(2, background("0-1"))
        assertEquals(2, background("unknown"))
        assertEquals(7, capacity.update(true, 7) { error("Foreground must not read CPU affinity") })
        assertEquals(4, background("2-5"))
        assertEquals(1, background("0"))

        for (invalid in listOf("", "2-0", "-1", "0-2147483647", "0-2,unknown")) {
            assertEquals(
                invalid,
                7,
                BackgroundCpuCapacity().update(false, 7) { parseAllowedCpuCount(invalid) },
            )
        }
    }
}
