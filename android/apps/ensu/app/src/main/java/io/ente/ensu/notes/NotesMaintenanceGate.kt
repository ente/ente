package io.ente.ensu.notes

internal class NotesMaintenanceGate<T> {
    private var suspensions = 0
    @Volatile var active: T? = null
        private set

    val available: Boolean
        @Synchronized get() = suspensions == 0 && active == null

    @Synchronized fun admit(run: T): Boolean {
        if (!available) return false
        active = run
        return true
    }

    @Synchronized fun suspend(): T? {
        suspensions++
        return active
    }

    @Synchronized fun resume() {
        suspensions--
    }

    @Synchronized fun finish(run: T) {
        if (active === run) active = null
    }
}
