package io.ente.qr_scanner

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

class EnteQrScannerPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var nextPermissionRequestCode = 49700
    private val permissionCallbacks = mutableMapOf<Int, (Boolean) -> Unit>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        binding.platformViewRegistry.registerViewFactory(
            EnteQrScannerViewFactory.viewType,
            EnteQrScannerViewFactory(
                messenger = binding.binaryMessenger,
                activityProvider = { activityBinding?.activity },
                permissionRequester = ::requestCameraPermission,
            ),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        failPendingPermissionRequests()
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        failPendingPermissionRequests()
    }

    private fun requestCameraPermission(callback: (Boolean) -> Unit) {
        val activity = activityBinding?.activity
        val context = applicationContext
        if (activity == null || context == null) {
            callback(false)
            return
        }

        if (hasCameraPermission(context)) {
            callback(true)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            callback(true)
            return
        }

        val requestCode = nextPermissionRequestCode++
        permissionCallbacks[requestCode] = callback
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.CAMERA),
            requestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        val callback = permissionCallbacks.remove(requestCode) ?: return false
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        callback(granted)
        return true
    }

    private fun hasCameraPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun failPendingPermissionRequests() {
        val callbacks = permissionCallbacks.values.toList()
        permissionCallbacks.clear()
        callbacks.forEach { it(false) }
    }
}
