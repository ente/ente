package io.ente.photos.platform.devicehealth

sealed interface DeviceSignal<out T> {
    data class Available<T>(val value: T) : DeviceSignal<T>

    data object Unsupported : DeviceSignal<Nothing>

    data class Unavailable(val error: DeviceHealthError) : DeviceSignal<Nothing>
}

enum class DeviceHealthError {
    BATTERY_INTENT_MISSING,
    BATTERY_NOT_PRESENT,
    BATTERY_LEVEL_MISSING,
    BATTERY_ACCESS_DENIED,
    BATTERY_READ_FAILED,
    THERMAL_STATUS_UNKNOWN,
    THERMAL_READ_FAILED,
    MEMORY_TOTAL_MISSING,
    MEMORY_READ_FAILED,
}

data class BatteryReading(
    val levelPercent: Int,
    val temperatureCelsius: Double?,
    val health: BatteryHealth,
) {
    init {
        require(levelPercent in 0..100) { "Battery level is outside 0..100" }
        require(temperatureCelsius == null || temperatureCelsius.isFinite()) {
            "Battery temperature is not finite"
        }
    }
}

enum class BatteryHealth {
    GOOD,
    COLD,
    OVERHEATING,
    OVER_VOLTAGE,
    DEAD,
    FAILURE,
    UNKNOWN,
}

enum class ThermalState {
    NOMINAL,
    LIGHT,
    MODERATE,
    SERIOUS,
    CRITICAL,
    EMERGENCY,
    SHUTDOWN,
}

data class DeviceHealthSnapshot(
    val observedAtMs: Long,
    val battery: DeviceSignal<BatteryReading>,
    val thermal: DeviceSignal<ThermalState>,
) {
    init {
        require(observedAtMs > 0) { "Observation time must be positive" }
    }
}
