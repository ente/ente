package io.ente.qr_scanner

data class EnteQrScannerOverlay(
    val cutOutSize: Double = 260.0,
) {
    companion object {
        fun from(arguments: Any?): EnteQrScannerOverlay {
            val map = arguments as? Map<*, *> ?: return EnteQrScannerOverlay()
            return EnteQrScannerOverlay(
                cutOutSize = (map["cutOutSize"] as? Number)?.toDouble() ?: 260.0,
            )
        }
    }
}
