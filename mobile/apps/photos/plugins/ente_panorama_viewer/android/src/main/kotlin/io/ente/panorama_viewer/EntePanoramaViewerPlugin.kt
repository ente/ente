package io.ente.panorama_viewer

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EntePanoramaViewerPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    SensorEventListener {
    private lateinit var windowManager: WindowManager
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var sensorManager: SensorManager? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(resolveSensor() != null)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        val selectedSensor = resolveSensor()
        if (selectedSensor == null) {
            events.error("motion_unavailable", "Device orientation is unavailable", null)
            return
        }
        eventSink = events
        val registered =
            sensorManager?.registerListener(
                this,
                selectedSensor,
                SensorManager.SENSOR_DELAY_GAME,
            ) == true
        if (!registered) {
            eventSink = null
            events.error("motion_unavailable", "Failed to start device orientation", null)
        }
    }

    override fun onCancel(arguments: Any?) {
        stop()
    }

    override fun onSensorChanged(event: SensorEvent) {
        val quaternion = FloatArray(4)
        SensorManager.getQuaternionFromVector(quaternion, event.values)
        val rotation = windowManager.defaultDisplay.rotation
        eventSink?.success(
            listOf(
                quaternion[0].toDouble(),
                quaternion[1].toDouble(),
                quaternion[2].toDouble(),
                quaternion[3].toDouble(),
                rotation,
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        sensorManager = null
    }

    private fun resolveSensor(): Sensor? {
        return sensorManager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    }

    private fun stop() {
        sensorManager?.unregisterListener(this)
        eventSink = null
    }

    companion object {
        private const val METHOD_CHANNEL = "io.ente.panorama_viewer/motion"
        private const val EVENT_CHANNEL = "io.ente.panorama_viewer/motion_events"
    }
}
