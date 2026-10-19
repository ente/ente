package io.ente.ensu.llm

import org.junit.Assert.assertEquals
import org.junit.Test

class LlmModelSelectionTest {
    @Test
    fun modelDefaultsOverridesAndFallbacksRespectAllocationLimits() {
        for (requested in listOf(null, 0, 12000)) {
            val selection = LlmModelSelection("lfm-350m", requested)
            assertEquals(listOf(2048, 1024), selection.contextCandidates())
            assertEquals(128, selection.batchSize)
        }
        val standard = LlmModelSelection("lfm-vl-1.6b")
        assertEquals(listOf(12000, 8192, 4096, 2048, 1024), standard.contextCandidates())
        assertEquals(512, standard.batchSize)

        for (id in listOf("lfm-350m", "lfm-vl-1.6b")) {
            assertEquals(listOf(512), LlmModelSelection(id, 512).contextCandidates())
            assertEquals(listOf(1536, 1024), LlmModelSelection(id, 1536).contextCandidates())
        }
    }
}
