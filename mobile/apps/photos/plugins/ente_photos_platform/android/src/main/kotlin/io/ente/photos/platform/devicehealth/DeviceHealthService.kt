package io.ente.photos.platform.devicehealth

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager

class DeviceHealthService(context: Context) {
    private val context = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var observer: ((DeviceHealthSnapshot) -> Unit)? = null
    private var receiverRegistered = false
    private var thermalListenerRegistered = false
    private var snapshotPending = false
    private var lastState: HealthState? = null

    private val batteryReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                scheduleSnapshot()
            }
        }

    private val thermalListener =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            PowerManager.OnThermalStatusChangedListener { scheduleSnapshot() }
        } else {
            null
        }

    fun snapshot(): DeviceHealthSnapshot =
        DeviceHealthSnapshot(
            observedAtMs = System.currentTimeMillis(),
            battery = batterySnapshot(),
            thermal = thermalSnapshot(),
        )

    fun memorySnapshot(): DeviceSignal<Long> =
        try {
            val info = ActivityManager.MemoryInfo()
            context.getSystemService(ActivityManager::class.java).getMemoryInfo(info)
            if (info.totalMem > 0) {
                DeviceSignal.Available(info.totalMem)
            } else {
                DeviceSignal.Unavailable(DeviceHealthError.MEMORY_TOTAL_MISSING)
            }
        } catch (_: RuntimeException) {
            DeviceSignal.Unavailable(DeviceHealthError.MEMORY_READ_FAILED)
        }

    fun startObserving(observer: (DeviceHealthSnapshot) -> Unit) {
        requireMainThread()
        stopObserving()
        this.observer = observer
        registerBatteryReceiver()
        registerThermalListener()
        scheduleSnapshot()
    }

    fun stopObserving() {
        requireMainThread()
        observer = null
        lastState = null
        snapshotPending = false
        mainHandler.removeCallbacksAndMessages(null)
        unregisterBatteryReceiver()
        unregisterThermalListener()
    }

    private fun registerBatteryReceiver() {
        receiverRegistered =
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.registerReceiver(
                        batteryReceiver,
                        IntentFilter(Intent.ACTION_BATTERY_CHANGED),
                        Context.RECEIVER_EXPORTED,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    context.registerReceiver(
                        batteryReceiver,
                        IntentFilter(Intent.ACTION_BATTERY_CHANGED),
                    )
                }
                true
            } catch (_: RuntimeException) {
                false
            }
    }

    private fun registerThermalListener() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        thermalListenerRegistered =
            try {
                context.getSystemService(PowerManager::class.java)
                    .addThermalStatusListener(context.mainExecutor, requireNotNull(thermalListener))
                true
            } catch (_: RuntimeException) {
                false
            }
    }

    private fun unregisterBatteryReceiver() {
        if (!receiverRegistered) return
        try {
            context.unregisterReceiver(batteryReceiver)
        } catch (_: IllegalArgumentException) {
            // The platform already removed the receiver.
        }
        receiverRegistered = false
    }

    private fun unregisterThermalListener() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !thermalListenerRegistered) return
        try {
            context.getSystemService(PowerManager::class.java)
                .removeThermalStatusListener(requireNotNull(thermalListener))
        } catch (_: RuntimeException) {
            // No observer remains during teardown.
        }
        thermalListenerRegistered = false
    }

    private fun scheduleSnapshot() {
        if (observer == null || snapshotPending) return
        snapshotPending = true
        mainHandler.post {
            snapshotPending = false
            val observer = observer ?: return@post
            val snapshot = snapshot()
            val state = HealthState(snapshot.battery, snapshot.thermal)
            if (state != lastState) {
                lastState = state
                observer(snapshot)
            }
        }
    }

    private fun batterySnapshot(): DeviceSignal<BatteryReading> {
        return try {
            val intent = stickyBatteryIntent()
                ?: return DeviceSignal.Unavailable(DeviceHealthError.BATTERY_INTENT_MISSING)
            if (!intent.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true)) {
                return DeviceSignal.Unavailable(DeviceHealthError.BATTERY_NOT_PRESENT)
            }
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level < 0 || scale <= 0 || level > scale) {
                return DeviceSignal.Unavailable(DeviceHealthError.BATTERY_LEVEL_MISSING)
            }
            val temperature = intent.getIntExtra(
                BatteryManager.EXTRA_TEMPERATURE,
                Int.MIN_VALUE,
            )
            DeviceSignal.Available(
                BatteryReading(
                    levelPercent = ((level.toDouble() / scale) * 100).toInt(),
                    temperatureCelsius =
                        temperature.takeUnless { it == Int.MIN_VALUE }?.div(10.0),
                    health = batteryHealth(
                        intent.getIntExtra(
                            BatteryManager.EXTRA_HEALTH,
                            BatteryManager.BATTERY_HEALTH_UNKNOWN,
                        ),
                    ),
                ),
            )
        } catch (_: SecurityException) {
            DeviceSignal.Unavailable(DeviceHealthError.BATTERY_ACCESS_DENIED)
        } catch (_: RuntimeException) {
            DeviceSignal.Unavailable(DeviceHealthError.BATTERY_READ_FAILED)
        }
    }

    private fun stickyBatteryIntent(): Intent? {
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(null, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(null, filter)
        }
    }

    private fun thermalSnapshot(): DeviceSignal<ThermalState> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return DeviceSignal.Unsupported
        return try {
            val state = thermalState(
                context.getSystemService(PowerManager::class.java).currentThermalStatus,
            ) ?: return DeviceSignal.Unavailable(DeviceHealthError.THERMAL_STATUS_UNKNOWN)
            DeviceSignal.Available(state)
        } catch (_: RuntimeException) {
            DeviceSignal.Unavailable(DeviceHealthError.THERMAL_READ_FAILED)
        }
    }

    private fun batteryHealth(value: Int): BatteryHealth =
        when (value) {
            BatteryManager.BATTERY_HEALTH_GOOD -> BatteryHealth.GOOD
            BatteryManager.BATTERY_HEALTH_COLD -> BatteryHealth.COLD
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> BatteryHealth.OVERHEATING
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> BatteryHealth.OVER_VOLTAGE
            BatteryManager.BATTERY_HEALTH_DEAD -> BatteryHealth.DEAD
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> BatteryHealth.FAILURE
            else -> BatteryHealth.UNKNOWN
        }

    private fun thermalState(value: Int): ThermalState? =
        when (value) {
            PowerManager.THERMAL_STATUS_NONE -> ThermalState.NOMINAL
            PowerManager.THERMAL_STATUS_LIGHT -> ThermalState.LIGHT
            PowerManager.THERMAL_STATUS_MODERATE -> ThermalState.MODERATE
            PowerManager.THERMAL_STATUS_SEVERE -> ThermalState.SERIOUS
            PowerManager.THERMAL_STATUS_CRITICAL -> ThermalState.CRITICAL
            PowerManager.THERMAL_STATUS_EMERGENCY -> ThermalState.EMERGENCY
            PowerManager.THERMAL_STATUS_SHUTDOWN -> ThermalState.SHUTDOWN
            else -> null
        }

    private fun requireMainThread() {
        check(Looper.myLooper() == Looper.getMainLooper()) {
            "Device health observation must be managed from the main thread"
        }
    }

    private data class HealthState(
        val battery: DeviceSignal<BatteryReading>,
        val thermal: DeviceSignal<ThermalState>,
    )
}
