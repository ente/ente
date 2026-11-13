package io.ente.qr_scanner

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class EnteQrScannerViewFactory(
    private val messenger: BinaryMessenger,
    private val activityProvider: () -> Activity?,
    private val permissionRequester: ((Boolean) -> Unit) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, platformViewId: Int, args: Any?): PlatformView {
        return EnteQrScannerView(
            context = context,
            messenger = messenger,
            platformViewId = platformViewId,
            overlay = EnteQrScannerOverlay.from(args),
            activityProvider = activityProvider,
            permissionRequester = permissionRequester,
        )
    }

    companion object {
        const val viewType = "io.ente.qr_scanner/view"
    }
}
