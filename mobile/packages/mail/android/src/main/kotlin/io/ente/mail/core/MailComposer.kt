package io.ente.mail.core

import android.app.Activity
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.MainThread
import androidx.core.content.FileProvider
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MailComposer(
    private val context: Context
) {
    private sealed interface Preparation {
        data class Ready(
            val intent: Intent,
            val attachment: AttachmentStore.StageResult.Staged?
        ) : Preparation

        data class Unavailable(val reason: MailUnavailableReason) : Preparation
    }

    private var isComposing = false
    private var isClosed = false
    private val attachmentStore = AttachmentStore(context.cacheDir.resolve("ente_mail"))
    private val executor: ExecutorService = newExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @MainThread
    fun compose(
        request: MailRequest,
        activityProvider: () -> Activity?,
        completion: (MailResult) -> Unit
    ) {
        if (isClosed || activityProvider() == null) {
            completion(MailResult.Unavailable(MailUnavailableReason.PRESENTATION_FAILED))
            return
        }
        if (isComposing) {
            completion(MailResult.Unavailable(MailUnavailableReason.COMPOSER_BUSY))
            return
        }
        isComposing = true
        executor.execute {
            val preparation = try {
                prepare(request)
            } catch (_: Exception) {
                Preparation.Unavailable(MailUnavailableReason.PRESENTATION_FAILED)
            }
            mainHandler.post {
                if (isClosed) {
                    if (preparation is Preparation.Ready) discard(preparation)
                    return@post
                }
                val result = when (preparation) {
                    is Preparation.Unavailable -> MailResult.Unavailable(preparation.reason)
                    is Preparation.Ready -> activityProvider()?.let { launch(it, preparation) }
                        ?: run {
                            discard(preparation)
                            MailResult.Unavailable(MailUnavailableReason.PRESENTATION_FAILED)
                        }
                }
                isComposing = false
                completion(result)
            }
        }
    }

    @MainThread
    fun close() {
        if (isClosed) return
        isClosed = true
        executor.shutdownNow()
    }

    private fun prepare(request: MailRequest): Preparation {
        attachmentStore.pruneExpired()
        return if (request.attachment == null) {
            prepareMailto(request)
        } else {
            prepareAttachment(request, request.attachment)
        }
    }

    private fun launch(activity: Activity, prepared: Preparation.Ready): MailResult = try {
        activity.startActivity(prepared.intent)
        MailResult.Launched
    } catch (_: Exception) {
        discard(prepared)
        MailResult.Unavailable(MailUnavailableReason.PRESENTATION_FAILED)
    }

    private fun discard(prepared: Preparation.Ready) {
        prepared.attachment?.let(attachmentStore::discard)
    }

    private fun prepareMailto(request: MailRequest): Preparation {
        val intent = Intent(Intent.ACTION_SENDTO, request.mailtoUri())
        if (queryActivities(intent).isEmpty()) {
            return Preparation.Unavailable(MailUnavailableReason.NO_MAIL_CLIENT)
        }
        return Preparation.Ready(Intent.createChooser(intent, null), null)
    }

    private fun prepareAttachment(
        request: MailRequest,
        attachment: MailAttachment
    ): Preparation {
        val mailPackages = queryActivities(
            Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        ).mapTo(mutableSetOf()) { it.activityInfo.packageName }
        if (mailPackages.isEmpty()) {
            return Preparation.Unavailable(MailUnavailableReason.NO_MAIL_CLIENT)
        }

        val targets = queryActivities(
            Intent(Intent.ACTION_SEND).setType(attachment.mimeType)
        ).filter { it.activityInfo.packageName in mailPackages }
            .distinctBy { it.activityInfo.packageName to it.activityInfo.name }
        if (targets.isEmpty()) {
            return Preparation.Unavailable(
                MailUnavailableReason.ATTACHMENT_COMPOSER_UNAVAILABLE
            )
        }

        val staged = when (val result = attachmentStore.stage(attachment)) {
            is AttachmentStore.StageResult.Staged -> result
            is AttachmentStore.StageResult.Unavailable -> {
                return Preparation.Unavailable(result.reason)
            }
        }
        return try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.ente_mail.attachments",
                staged.file
            )
            val intents = targets.map { target ->
                Intent(Intent.ACTION_SEND).apply {
                    component = ComponentName(
                        target.activityInfo.packageName,
                        target.activityInfo.name
                    )
                    type = attachment.mimeType
                    putExtra(Intent.EXTRA_EMAIL, arrayOf(request.recipient))
                    putExtra(Intent.EXTRA_SUBJECT, request.subject)
                    putExtra(Intent.EXTRA_TEXT, request.body)
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newUri(
                        context.contentResolver,
                        staged.file.name,
                        uri
                    )
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            val chooser = Intent.createChooser(intents.first(), null).apply {
                if (intents.size > 1) {
                    putExtra(Intent.EXTRA_ALTERNATE_INTENTS, intents.drop(1).toTypedArray())
                }
                clipData = intents.first().clipData
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            Preparation.Ready(chooser, staged)
        } catch (_: Exception) {
            attachmentStore.discard(staged)
            Preparation.Unavailable(MailUnavailableReason.PRESENTATION_FAILED)
        }
    }

    private fun queryActivities(intent: Intent): List<ResolveInfo> {
        val packageManager = context.packageManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(
                    PackageManager.MATCH_DEFAULT_ONLY.toLong()
                )
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }
    }

    private companion object {
        fun newExecutor(): ExecutorService = Executors.newSingleThreadExecutor { task ->
            Thread(task, "mail-composer").apply { isDaemon = true }
        }
    }
}

private fun MailRequest.mailtoUri(): Uri {
    val query = buildList {
        if (subject.isNotEmpty()) add("subject=${Uri.encode(subject)}")
        if (body.isNotEmpty()) add("body=${Uri.encode(body)}")
    }
    val encodedRecipient = Uri.encode(recipient, "@+")
    return Uri.parse(
        buildString {
            append("mailto:")
            append(encodedRecipient)
            if (query.isNotEmpty()) {
                append('?')
                append(query.joinToString("&"))
            }
        }
    )
}
