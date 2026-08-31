package io.ente.photos.platform.flutter

import io.ente.photos.platform.devicehealth.BatteryHealth
import io.ente.photos.platform.devicehealth.BatteryReading
import io.ente.photos.platform.devicehealth.DeviceHealthError
import io.ente.photos.platform.devicehealth.DeviceHealthService
import io.ente.photos.platform.devicehealth.DeviceHealthSnapshot
import io.ente.photos.platform.devicehealth.DeviceSignal
import io.ente.photos.platform.devicehealth.ThermalState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class DeviceHealthChannelAdapter :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var service: DeviceHealthService
    private var eventSink: EventChannel.EventSink? = null

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        service = DeviceHealthService(binding.applicationContext)
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) =
        when (call.method) {
            "deviceHealth.getSnapshot" -> result.success(service.snapshot().toChannelMap())

            "deviceHealth.getMemorySnapshot" ->
                result.success(service.memorySnapshot().toMemoryChannelMap())

            else -> result.notImplemented()
        }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        service.startObserving { snapshot ->
            eventSink?.success(snapshot.toChannelMap())
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        service.stopObserving()
    }

    fun detach() {
        eventSink = null
        service.stopObserving()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private fun DeviceHealthSnapshot.toChannelMap(): Map<String, Any?> =
        mapOf(
            "platform" to "android",
            "observedAtMs" to observedAtMs,
            "battery" to battery.toBatteryChannelMap(),
            "thermal" to thermal.toThermalChannelMap(),
        )

    private fun DeviceSignal<BatteryReading>.toBatteryChannelMap(): Map<String, Any?> =
        when (this) {
            is DeviceSignal.Available ->
                buildMap {
                    put("status", "available")
                    put("levelPercent", value.levelPercent)
                    value.temperatureCelsius?.let { put("temperatureCelsius", it) }
                    put("health", value.health.channelValue)
                }

            DeviceSignal.Unsupported -> mapOf("status" to "unsupported")
            is DeviceSignal.Unavailable -> unavailableChannelMap(error)
        }

    private fun DeviceSignal<ThermalState>.toThermalChannelMap(): Map<String, Any?> =
        when (this) {
            is DeviceSignal.Available ->
                mapOf("status" to "available", "state" to value.channelValue)

            DeviceSignal.Unsupported -> mapOf("status" to "unsupported")
            is DeviceSignal.Unavailable -> unavailableChannelMap(error)
        }

    private fun DeviceSignal<Long>.toMemoryChannelMap(): Map<String, Any?> =
        when (this) {
            is DeviceSignal.Available -> mapOf("status" to "available", "totalBytes" to value)
            DeviceSignal.Unsupported -> mapOf("status" to "unsupported")
            is DeviceSignal.Unavailable -> unavailableChannelMap(error)
        }

    private val BatteryHealth.channelValue: String
        get() =
            when (this) {
                BatteryHealth.GOOD -> "good"
                BatteryHealth.COLD -> "cold"
                BatteryHealth.OVERHEATING -> "overheating"
                BatteryHealth.OVER_VOLTAGE -> "overVoltage"
                BatteryHealth.DEAD -> "dead"
                BatteryHealth.FAILURE -> "failure"
                BatteryHealth.UNKNOWN -> "unknown"
            }

    private val ThermalState.channelValue: String
        get() = name.lowercase()

    private fun unavailableChannelMap(error: DeviceHealthError): Map<String, Any?> =
        mapOf("status" to "unavailable", "errorCode" to error.channelValue)

    private val DeviceHealthError.channelValue: String
        get() =
            when (this) {
                DeviceHealthError.BATTERY_INTENT_MISSING -> "battery_intent_missing"
                DeviceHealthError.BATTERY_NOT_PRESENT -> "battery_not_present"
                DeviceHealthError.BATTERY_LEVEL_MISSING -> "battery_level_missing"
                DeviceHealthError.BATTERY_ACCESS_DENIED -> "battery_access_denied"
                DeviceHealthError.BATTERY_READ_FAILED -> "battery_read_failed"
                DeviceHealthError.THERMAL_STATUS_UNKNOWN -> "thermal_status_unknown"
                DeviceHealthError.THERMAL_READ_FAILED -> "thermal_read_failed"
                DeviceHealthError.MEMORY_TOTAL_MISSING -> "memory_total_missing"
                DeviceHealthError.MEMORY_READ_FAILED -> "memory_read_failed"
            }

    private companion object {
        const val METHOD_CHANNEL = "io.ente.photos.platform/device_health"
        const val EVENT_CHANNEL = "io.ente.photos.platform/device_health_events"
    }
}
