package io.ente.photos.platform.flutter

import io.ente.photos.platform.country.CountryNamesService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class CountryNamesChannelAdapter : MethodChannel.MethodCallHandler {
    private val service = CountryNamesService()
    private lateinit var channel: MethodChannel

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) =
        when (call.method) {
            "get" -> {
                val arguments = call.arguments as? Map<*, *>
                    ?: return result.error("invalid_arguments", "Expected country name arguments", null)
                val locale = arguments["locale"] as? String
                    ?: return result.error("invalid_locale", "Expected a locale identifier", null)
                val nativeLocales = parseNativeLocales(arguments["nativeLocales"])
                    ?: return result.error("invalid_native_locales", "Expected native country locales", null)
                val names = service.names(locale, nativeLocales)
                result.success(
                    mapOf(
                        "region" to names.region,
                        "names" to names.names,
                        "nativeNames" to names.nativeNames,
                    ),
                )
            }

            else -> result.notImplemented()
        }

    fun detach() = channel.setMethodCallHandler(null)

    private fun parseNativeLocales(value: Any?): Map<String, List<String>>? {
        val map = value as? Map<*, *> ?: return null
        val result = mutableMapOf<String, List<String>>()
        for ((code, localeValues) in map) {
            if (code !is String || localeValues !is List<*>) return null
            val locales = localeValues.map { it as? String ?: return null }
            result[code] = locales
        }
        return result
    }

    private companion object {
        const val CHANNEL = "io.ente.photos.platform/country_names"
    }
}
