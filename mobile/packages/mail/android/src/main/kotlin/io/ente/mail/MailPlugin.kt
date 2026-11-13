package io.ente.mail

import android.app.Activity
import io.ente.mail.core.MailAttachment
import io.ente.mail.core.MailComposer
import io.ente.mail.core.MailRequest
import io.ente.mail.core.MailResult
import io.ente.mail.core.MailUnavailableReason
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MailPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var composer: MailComposer
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        composer = MailComposer(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "compose") {
            result.notImplemented()
            return
        }
        val request = try {
            call.toRequest()
        } catch (error: IllegalArgumentException) {
            result.error("invalidDraft", error.message, null)
            return
        }
        composer.compose(request, { activity }) { outcome ->
            result.success(outcome.channelValue)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        activity = null
        channel.setMethodCallHandler(null)
        composer.close()
    }

    private companion object {
        const val CHANNEL = "io.ente.mail/composer"
    }
}

private val MailResult.channelValue: Map<String, String>
    get() = when (this) {
        MailResult.Launched -> mapOf("status" to "launched")
        is MailResult.Unavailable -> mapOf(
            "status" to "unavailable",
            "reason" to reason.channelValue
        )
    }

private val MailUnavailableReason.channelValue: String
    get() = when (this) {
        MailUnavailableReason.NO_MAIL_CLIENT -> "noMailClient"
        MailUnavailableReason.ATTACHMENT_COMPOSER_UNAVAILABLE -> {
            "attachmentComposerUnavailable"
        }
        MailUnavailableReason.ATTACHMENT_MISSING -> "attachmentMissing"
        MailUnavailableReason.ATTACHMENT_UNREADABLE -> "attachmentUnreadable"
        MailUnavailableReason.ATTACHMENT_TOO_LARGE -> "attachmentTooLarge"
        MailUnavailableReason.COMPOSER_BUSY -> "composerBusy"
        MailUnavailableReason.PRESENTATION_FAILED -> "presentationFailed"
    }

private fun MethodCall.toRequest(): MailRequest {
    val arguments = arguments as? Map<*, *>
        ?: throw IllegalArgumentException("Mail draft is missing")
    fun string(name: String): String = arguments[name] as? String
        ?: throw IllegalArgumentException("Mail draft has no $name")

    val attachment = arguments["attachment"]?.let { value ->
        val map = value as? Map<*, *>
            ?: throw IllegalArgumentException("Attachment is invalid")
        fun attachmentString(name: String): String = map[name] as? String
            ?: throw IllegalArgumentException("Attachment has no $name")

        MailAttachment(
            path = attachmentString("path"),
            mimeType = attachmentString("mimeType")
        )
    }
    return MailRequest(
        recipient = string("recipient"),
        subject = string("subject"),
        body = string("body"),
        attachment = attachment
    )
}
