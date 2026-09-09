package io.ente.ensu.llm

interface ModelMaintenance {
    fun suspendMaintenance(): AutoCloseable
    suspend fun awaitMaintenance()
    fun modelReadinessChanged()
}

internal suspend fun <T> ModelMaintenance?.withMaintenanceSuspended(block: suspend () -> T): T {
    val token = this?.suspendMaintenance()
    try {
        this?.awaitMaintenance()
        return block()
    } finally {
        token?.close()
    }
}
