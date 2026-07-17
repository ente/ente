package io.ente.ensu.logging

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class FileLogRepository(
    private val context: Context,
    private val maxLogFiles: Int = 5
) {

    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val writeMutex = Mutex()

    private val dateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    private val lineTimestampFormatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    private val logsDir: File = File(context.filesDir, "logs")

    init {
        ensureLogDir()
        pruneOldLogFiles()
    }

    fun log(level: LogLevel, message: String, details: String? = null, tag: String? = null, throwable: Throwable? = null) {
        val resolvedTag = tag ?: "ensu"
        val entry = buildLogEntry(
            level = level,
            message = message,
            details = details,
            tag = resolvedTag,
            throwable = throwable
        )

        // Also mirror to Logcat.
        when (level) {
            LogLevel.Info -> Log.i(resolvedTag, entry.message)
            LogLevel.Warning -> Log.w(resolvedTag, entry.message)
            LogLevel.Error -> {
                if (throwable != null) {
                    Log.e(resolvedTag, entry.message, throwable)
                } else {
                    Log.e(resolvedTag, entry.message)
                }
            }
        }

        val line = formatLine(entry)
        ioScope.launch {
            writeMutex.withLock {
                val file = todayLogFile()
                file.parentFile?.mkdirs()
                file.appendText(line)
            }
        }
    }

    fun logDirectory(): File = logsDir

    fun listLogFiles(): List<File> {
        ensureLogDir()
        return logsDir.listFiles()
            ?.filter { it.isFile && it.name.endsWith(".txt") }
            ?.sortedBy { it.name }
            .orEmpty()
    }

    suspend fun readLogText(file: File): String = withContext(Dispatchers.IO) {
        writeMutex.withLock {
            if (!file.exists()) return@withLock ""
            runCatching { file.readText() }.getOrDefault("")
        }
    }

    fun todayLogFile(): File {
        val name = "${dateFormatter.format(Date())}.txt"
        return File(logsDir, name)
    }

    suspend fun readTodayLogText(): String = withContext(Dispatchers.IO) {
        writeMutex.withLock {
            val file = todayLogFile()
            if (!file.exists()) return@withLock ""
            runCatching { file.readText() }.getOrDefault("")
        }
    }

    suspend fun readTodayEntries(): List<LogEntry> = withContext(Dispatchers.IO) {
        parseLogEntries(readTodayLogText()).reversed()
    }

    suspend fun createLogsZip(outputDir: File = context.cacheDir): File = withContext(Dispatchers.IO) {
        ensureLogDir()
        pruneOldLogFiles()

        val now = Date()
        val out = File(outputDir, "ensu-logs-${dateFormatter.format(now)}-${System.currentTimeMillis()}.zip")
        if (out.exists()) out.delete()

        ZipOutputStream(BufferedOutputStream(FileOutputStream(out))).use { zipOut ->
            logsDir.listFiles()?.sortedBy { it.name }?.forEach { file ->
                if (!file.isFile) return@forEach
                val entry = ZipEntry(file.name)
                zipOut.putNextEntry(entry)
                BufferedInputStream(FileInputStream(file)).use { input ->
                    input.copyTo(zipOut)
                }
                zipOut.closeEntry()
            }
        }
        out
    }

    private fun ensureLogDir() {
        if (!logsDir.exists()) {
            logsDir.mkdirs()
        }
    }

    private fun pruneOldLogFiles() {
        val files = logsDir.listFiles()?.toList().orEmpty()
            .filter { it.isFile && it.name.endsWith(".txt") }
            .mapNotNull { file ->
                val name = file.name.removeSuffix(".txt")
                val date = runCatching { dateFormatter.parse(name) }.getOrNull() ?: return@mapNotNull null
                file to date.time
            }
            .sortedBy { it.second }
            .map { it.first }

        if (files.size <= maxLogFiles) return
        val toDelete = files.take(files.size - maxLogFiles)
        toDelete.forEach { runCatching { it.delete() } }
    }

    private fun formatLine(entry: LogEntry): String = buildString {
        val timestamp = lineTimestampFormatter.format(Date(entry.timestampMillis))
        append("[${entry.tag}][${levelToken(entry.level)}] [$timestamp] ${entry.message}\n")
        entry.details?.lineSequence()?.forEach { append(it).append('\n') }
    }

    private fun parseLogEntries(text: String): List<LogEntry> {
        val entries = mutableListOf<LogEntry>()
        text.lineSequence().forEach { rawLine ->
            val line = rawLine.trimEnd()
            if (line.isBlank()) return@forEach

            val match = logLineRegex.matchEntire(line)
            if (match != null) {
                val (tag, level, timestamp, message) = match.destructured
                entries.add(
                    LogEntry(
                        id = UUID.randomUUID().toString(),
                        timestampMillis = runCatching { lineTimestampFormatter.parse(timestamp)?.time }
                            .getOrNull() ?: System.currentTimeMillis(),
                        level = parseLevel(level),
                        tag = tag,
                        message = message
                    )
                )
            } else {
                val last = entries.lastOrNull()
                if (last != null) {
                    entries[entries.lastIndex] =
                        last.copy(details = listOfNotNull(last.details, line).joinToString("\n"))
                } else {
                    entries.add(
                        LogEntry(
                            id = UUID.randomUUID().toString(),
                            timestampMillis = System.currentTimeMillis(),
                            level = LogLevel.Info,
                            tag = "Log",
                            message = line
                        )
                    )
                }
            }
        }
        return entries
    }

    private fun levelToken(level: LogLevel): String = when (level) {
        LogLevel.Info -> "INFO"
        LogLevel.Warning -> "WARN"
        LogLevel.Error -> "ERROR"
    }

    private fun parseLevel(token: String): LogLevel = when (token.uppercase()) {
        "WARN", "WARNING" -> LogLevel.Warning
        "ERROR" -> LogLevel.Error
        else -> LogLevel.Info
    }

    companion object {
        private val logLineRegex = Regex("\\[(.+?)]\\[(.+?)] \\[(.+?)] (.*)")
    }
}
