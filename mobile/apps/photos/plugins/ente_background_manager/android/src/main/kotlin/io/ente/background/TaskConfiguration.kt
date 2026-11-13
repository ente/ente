package io.ente.background

import org.json.JSONObject

internal data class TaskConfiguration(
    val identifier: String,
    val kind: String,
    val frequencyMs: Long,
    val initialDelayMs: Long,
    val flexMs: Long?,
    val requiresNetwork: Boolean,
    val requiresCharging: Boolean,
    val requiresDeviceIdle: Boolean,
    val runBudgetMs: Long?,
    val foregroundStopTimeoutMs: Long?,
    val callbackHandle: Long,
) {
    fun encode(): String =
        JSONObject(
                mapOf(
                    "identifier" to identifier,
                    "kind" to kind,
                    "frequencyMs" to frequencyMs,
                    "initialDelayMs" to initialDelayMs,
                    "flexMs" to flexMs,
                    "requiresNetwork" to requiresNetwork,
                    "requiresCharging" to requiresCharging,
                    "requiresDeviceIdle" to requiresDeviceIdle,
                    "runBudgetMs" to runBudgetMs,
                    "foregroundStopTimeoutMs" to foregroundStopTimeoutMs,
                    "callbackHandle" to callbackHandle,
                )
            )
            .toString()

    companion object {
        fun decode(
            json: JSONObject,
            callbackHandle: Long = json.getLong("callbackHandle"),
        ): TaskConfiguration {
            fun duration(key: String): Long? =
                if (json.isNull(key)) null
                else json.getLong(key).also { require(it >= 0) { "$key must not be negative" } }

            val identifier = json.getString("identifier")
            val kind = json.getString("kind")
            val frequency = json.getLong("frequencyMs")
            val flex = duration("flexMs")
            require(identifier.isNotBlank()) { "Task identifier must not be blank" }
            require(kind == "refresh" || kind == "processing") {
                "Task kind must be refresh or processing"
            }
            require(frequency >= 15 * 60 * 1000L) { "Frequency must be at least 15 minutes" }
            require(flex == null || flex in 5 * 60 * 1000L..frequency) {
                "Flex must be at least 5 minutes and no greater than frequency"
            }
            require(callbackHandle != 0L) { "A retained background dispatcher is required" }
            return TaskConfiguration(
                identifier,
                kind,
                frequency,
                duration("initialDelayMs") ?: 0,
                flex,
                json.optBoolean("requiresNetwork"),
                json.optBoolean("requiresCharging"),
                json.optBoolean("requiresDeviceIdle"),
                duration("runBudgetMs"),
                duration("foregroundStopTimeoutMs"),
                callbackHandle,
            )
        }
    }
}
