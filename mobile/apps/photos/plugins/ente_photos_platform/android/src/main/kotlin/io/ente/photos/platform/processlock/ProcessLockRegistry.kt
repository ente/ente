package io.ente.photos.platform.processlock

import android.util.Log

object ProcessLockRegistry {
    private class Holder(
        val instanceId: String,
        var origin: String,
        var operation: String,
        val acquiredAtNanos: Long,
    )

    private const val TAG = "ProcessLockRegistry"

    private val guard = Any()
    private val holders = HashMap<String, Holder>()

    fun tryAcquire(
        name: String,
        instanceId: String,
        origin: String,
        operation: String,
    ): Boolean =
        synchronized(guard) {
            val current = holders[name]
            when {
                current == null -> {
                    holders[name] = Holder(instanceId, origin, operation, System.nanoTime())
                    true
                }
                // A Dart hot restart can leave this plugin instance holding the lock.
                current.instanceId == instanceId -> {
                    Log.i(
                        TAG,
                        "Healed same-instance holder of '$name' " +
                            "(${current.origin}/${current.operation} -> $origin/$operation)",
                    )
                    current.origin = origin
                    current.operation = operation
                    true
                }
                else -> false
            }
        }

    fun release(name: String, instanceId: String): Boolean =
        synchronized(guard) {
            if (holders[name]?.instanceId == instanceId) {
                holders.remove(name)
                true
            } else {
                false
            }
        }

    fun releaseAllForInstance(instanceId: String) {
        synchronized(guard) {
            val released = holders.filterValues { it.instanceId == instanceId }
            if (released.isNotEmpty()) {
                Log.w(
                    TAG,
                    "Engine detach released lock(s) still held: " +
                        released.entries.joinToString {
                            "${it.key} (${it.value.origin}/${it.value.operation})"
                        },
                )
            }
            holders.values.removeAll { it.instanceId == instanceId }
        }
    }

    fun state(name: String): Map<String, Any>? =
        synchronized(guard) {
            holders[name]?.let {
                mapOf(
                    "origin" to it.origin,
                    "operation" to it.operation,
                    "heldForMillis" to (System.nanoTime() - it.acquiredAtNanos) / 1_000_000,
                )
            }
        }
}
