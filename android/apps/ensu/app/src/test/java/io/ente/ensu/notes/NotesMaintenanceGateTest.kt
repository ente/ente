package io.ente.ensu.notes

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class NotesMaintenanceGateTest {
    @Test
    fun suspensionPreventsAdmissionUntilResumed() {
        val gate = NotesMaintenanceGate<Any>()
        val run = Any()

        assertNull(gate.suspend())
        assertFalse(gate.admit(run))
        gate.resume()

        assertTrue(gate.admit(run))
    }

    @Test
    fun suspensionReturnsTheActiveRun() {
        val gate = NotesMaintenanceGate<Any>()
        val run = Any()
        assertTrue(gate.admit(run))

        assertSame(run, gate.suspend())
        gate.finish(run)
        assertFalse(gate.available)
        gate.resume()

        assertTrue(gate.available)
    }
}
