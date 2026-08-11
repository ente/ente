package io.ente.photos.platform

internal data class MlProcessLockState(
    val token: String,
    val pluginInstanceId: String,
    val origin: String,
    val operation: String,
    val acquiredAtNanos: Long,
)

internal data class MlProcessLockAcquireResult(
    val acquired: Boolean,
    val holder: MlProcessLockState,
)

internal object MlProcessLockRegistry {
    private val monitor = Any()
    private var holder: MlProcessLockState? = null

    fun tryAcquire(
        pluginInstanceId: String,
        token: String,
        origin: String,
        operation: String,
        acquiredAtNanos: Long = System.nanoTime(),
    ): MlProcessLockAcquireResult =
        synchronized(monitor) {
            val current = holder
            if (current == null) {
                val acquired =
                    MlProcessLockState(
                        token = token,
                        pluginInstanceId = pluginInstanceId,
                        origin = origin,
                        operation = operation,
                        acquiredAtNanos = acquiredAtNanos,
                    )
                holder = acquired
                MlProcessLockAcquireResult(true, acquired)
            } else {
                MlProcessLockAcquireResult(
                    current.pluginInstanceId == pluginInstanceId && current.token == token,
                    current,
                )
            }
        }

    fun release(pluginInstanceId: String, token: String): Boolean =
        synchronized(monitor) {
            val current = holder
            if (current?.pluginInstanceId != pluginInstanceId || current.token != token) {
                return@synchronized false
            }
            holder = null
            true
        }

    fun resetForInstance(pluginInstanceId: String): Boolean =
        synchronized(monitor) {
            if (holder?.pluginInstanceId != pluginInstanceId) {
                return@synchronized false
            }
            holder = null
            true
        }

    fun state(): MlProcessLockState? = synchronized(monitor) { holder }
}
