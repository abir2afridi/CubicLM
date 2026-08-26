package com.cubiclm.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/**
 * Foreground service that downloads model files with HTTP Range resume.
 *
 * - Keeps running when the app is swiped away (foreground notification).
 * - Pause keeps the .part file — resume continues at the exact byte offset.
 * - Job metadata is persisted so START_STICKY restarts auto-resume downloads
 *   even after the process is killed by the system.
 */
class ModelDownloadService : Service() {

    class Job(
        val url: String,
        val filename: String,
        val modelsDir: String,
    ) {
        @Volatile var paused = false
        @Volatile var cancelled = false
    }

    companion object {
        const val ACTION_START = "com.cubiclm.app.download.START"
        const val ACTION_PAUSE_ALL = "com.cubiclm.app.download.PAUSE_ALL"
        const val ACTION_CANCEL_ALL = "com.cubiclm.app.download.CANCEL_ALL"
        const val EXTRA_URL = "url"
        const val EXTRA_FILENAME = "filename"
        const val EXTRA_MODELS_DIR = "modelsDir"
        private const val PREFS = "model_stream_downloads"
        private const val CHANNEL_ID = "cubiclm_model_downloads"
        private const val NOTIF_ID = 4210
        private const val UA =
            "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

        private val jobs = LinkedHashMap<String, Job>()
        private val lastProgress = ConcurrentHashMap<String, LongArray>()

        /** Wired by MainActivity — forwards progress into the Flutter channel. */
        @Volatile var emitter: ((String, Long, Long, Double, String) -> Unit)? = null

        @Volatile private var instance: ModelDownloadService? = null

        fun startJob(context: Context, url: String, rawFilename: String, modelsDir: String): String? {
            val filename = sanitize(rawFilename)
            synchronized(jobs) { if (jobs.containsKey(filename)) return null }
            val intent = Intent(context, ModelDownloadService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_URL, url)
                .putExtra(EXTRA_FILENAME, filename)
                .putExtra(EXTRA_MODELS_DIR, modelsDir)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                filename
            } catch (e: Exception) {
                null
            }
        }

        fun pauseJob(filename: String) {
            synchronized(jobs) { jobs[filename]?.paused = true }
        }

        fun cancelJob(filename: String) {
            synchronized(jobs) { jobs[filename]?.cancelled = true }
        }

        fun pauseAll() {
            synchronized(jobs) { jobs.values.forEach { it.paused = true } }
        }

        fun cancelAll() {
            synchronized(jobs) { jobs.values.forEach { it.cancelled = true } }
        }

        fun sanitize(f: String): String = f.replace(Regex("[^A-Za-z0-9._ ()+-]"), "_")

        /** Persisted jobs (Running/Paused/Failed) for reconcile queries. */
        fun persistedSnapshot(context: Context): List<Map<String, Any>> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val out = mutableListOf<Map<String, Any>>()
            synchronized(jobs) {
                for ((_, j) in jobs) {
                    out.add(
                        mapOf(
                            "filename" to j.filename,
                            "url" to j.url,
                            "modelsDir" to j.modelsDir,
                            "status" to "Running",
                        )
                    )
                }
            }
            for ((_, raw) in prefs.all) {
                val record = runCatching { JSONObject(raw as String) }.getOrNull() ?: continue
                val filename = record.optString("filename")
                val modelsDir = record.optString("modelsDir")
                if (filename.isBlank() || modelsDir.isBlank()) continue
                if (out.any { it["filename"] == filename }) continue
                val part = File(modelsDir, "$filename.part")
                out.add(
                    mapOf(
                        "filename" to filename,
                        "url" to record.optString("url"),
                        "modelsDir" to modelsDir,
                        "downloaded" to (if (part.exists()) part.length() else 0L),
                        "total" to record.optLong("total", 0L),
                        "status" to record.optString("status", "Paused"),
                    )
                )
            }
            return out
        }

        private fun persist(context: Context, job: Job, total: Long, status: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(
                    job.filename,
                    JSONObject()
                        .put("url", job.url)
                        .put("filename", job.filename)
                        .put("modelsDir", job.modelsDir)
                        .put("total", total)
                        .put("status", status)
                        .toString()
                )
                .apply()
        }

        private fun unpersist(context: Context, filename: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(filename)
                .apply()
        }

        fun emit(filename: String, copied: Long, total: Long, bps: Double, status: String) {
            if (status.startsWith("Downloading")) {
                instance?.trackProgress(filename, copied, total)
            }
            try {
                emitter?.invoke(filename, copied, total, bps, status)
            } catch (_: Exception) {}
        }
    }

    private var lastNotifUpdate = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        startInForeground("Preparing download…", -1, 0)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must reach foreground quickly on every start.
        ensureForeground()
        when (intent?.action) {
            ACTION_PAUSE_ALL -> pauseAll()
            ACTION_CANCEL_ALL -> cancelAll()
            ACTION_START -> {
                val url = intent.getStringExtra(EXTRA_URL)
                val filename = intent.getStringExtra(EXTRA_FILENAME)
                val modelsDir = intent.getStringExtra(EXTRA_MODELS_DIR)
                if (!url.isNullOrBlank() && !filename.isNullOrBlank() && !modelsDir.isNullOrBlank()) {
                    val added = synchronized(jobs) {
                        if (jobs.containsKey(filename)) false
                        else {
                            jobs[filename] = Job(url, filename, modelsDir)
                            true
                        }
                    }
                    if (added) spawnWorker(jobs[filename]!!)
                }
            }
            else -> {
                // START_STICKY redelivery after process death → auto-resume
                // everything still marked Running.
                for (entry in persistedSnapshot(this)) {
                    if (entry["status"] != "Running") continue
                    val filename = entry["filename"] as String
                    val added = synchronized(jobs) {
                        if (jobs.containsKey(filename)) false
                        else {
                            jobs[filename] = Job(
                                entry["url"] as String,
                                filename,
                                entry["modelsDir"] as String,
                            )
                            true
                        }
                    }
                    if (added) spawnWorker(jobs[filename]!!)
                }
            }
        }
        updateNotification(true)
        return START_STICKY
    }

    private fun spawnWorker(job: Job) {
        persist(this, job, 0, "Running")
        thread(name = "cubiclm-dl-${job.filename.hashCode()}") {
            download(job)
            var hasRemaining = false
            synchronized(jobs) {
                jobs.remove(job.filename)
                lastProgress.remove(job.filename)
                hasRemaining = jobs.isNotEmpty()
            }
            if (hasRemaining) {
                updateNotification(true)
            } else {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun download(job: Job) {
        var conn: HttpURLConnection? = null
        try {
            val dir = File(job.modelsDir)
            dir.mkdirs()
            val finalFile = File(dir, job.filename)
            val partFile = File(dir, "${job.filename}.part")

            if (finalFile.exists() && finalFile.length() > 0) {
                unpersist(this, job.filename)
                emit(job.filename, finalFile.length(), finalFile.length(), 0.0, "Download complete")
                return
            }

            var offset = if (partFile.exists()) partFile.length() else 0L

            fun connect(rangeOffset: Long): HttpURLConnection {
                val c = URL(job.url).openConnection() as HttpURLConnection
                c.connectTimeout = 20000
                c.readTimeout = 30000
                c.instanceFollowRedirects = true
                c.setRequestProperty("User-Agent", UA)
                c.setRequestProperty("Accept", "*/*")
                if (rangeOffset > 0) c.setRequestProperty("Range", "bytes=$rangeOffset-")
                c.connect()
                return c
            }

            var append = offset > 0
            conn = connect(if (append) offset else 0L)
            var code = conn.responseCode
            if (append && code != HttpURLConnection.HTTP_PARTIAL) {
                append = false
                offset = 0
                conn.disconnect()
                conn = connect(0L)
                code = conn.responseCode
            }
            if (code !in 200..299) throw IOException("HTTP $code")

            val rangeFullTotal = if (code == HttpURLConnection.HTTP_PARTIAL) {
                conn.getHeaderField("Content-Range")?.substringAfter('/')?.toLongOrNull() ?: -1L
            } else {
                -1L
            }
            val totalFull = when {
                rangeFullTotal > 0 -> rangeFullTotal
                conn.contentLengthLong > 0 ->
                    if (append) offset + conn.contentLengthLong else conn.contentLengthLong
                else -> -1L
            }
            if (totalFull > 0) persist(this, job, totalFull, "Running")

            val input = conn.inputStream
            val out = FileOutputStream(partFile, append)
            var received = offset
            var lastBytes = offset
            var lastTime = System.currentTimeMillis()
            var lastSpeed = 0.0
            var lastEmit = 0L
            val buffer = ByteArray(256 * 1024)

            out.use { sink ->
                while (true) {
                    if (job.cancelled || job.paused) break
                    val n = input.read(buffer)
                    if (n == -1) break
                    sink.write(buffer, 0, n)
                    received += n

                    val now = System.currentTimeMillis()
                    val elapsed = now - lastTime
                    if (elapsed >= 500) {
                        lastSpeed = (received - lastBytes).toDouble() / (elapsed / 1000.0)
                        lastBytes = received
                        lastTime = now
                    }
                    if (now - lastEmit >= 400) {
                        lastEmit = now
                        emit(job.filename, received, totalFull, lastSpeed, "Downloading...")
                    }
                }
                sink.flush()
            }

            when {
                job.cancelled -> {
                    partFile.delete()
                    unpersist(this, job.filename)
                    emit(job.filename, 0, 0, 0.0, "Download cancelled")
                }
                job.paused -> {
                    persist(this, job, if (totalFull > 0) totalFull else 0L, "Paused")
                    emit(job.filename, received, totalFull, 0.0, "Paused")
                }
                else -> {
                    if (totalFull > 0 && partFile.length() < totalFull) {
                        throw IOException("Incomplete download ${partFile.length()} of $totalFull")
                    }
                    if (finalFile.exists()) finalFile.delete()
                    if (!partFile.renameTo(finalFile)) {
                        throw IOException("Unable to finalize downloaded model")
                    }
                    unpersist(this, job.filename)
                    emit(job.filename, finalFile.length(), finalFile.length(), 0.0, "Download complete")
                }
            }
        } catch (e: Exception) {
            when {
                job.cancelled -> {
                    val part = File(File(job.modelsDir), "${job.filename}.part")
                    if (part.exists()) part.delete()
                    unpersist(this, job.filename)
                    emit(job.filename, 0, 0, 0.0, "Download cancelled")
                }
                job.paused -> {
                    persist(this, job, 0, "Paused")
                    emit(job.filename, 0, 0, 0.0, "Paused")
                }
                else -> {
                    persist(this, job, 0, "Failed")
                    emit(job.filename, 0, 0, 0.0, "Download failed: ${e.message}")
                }
            }
        } finally {
            conn?.disconnect()
        }
    }

    // ── Notification plumbing ──

    fun trackProgress(filename: String, received: Long, total: Long) {
        lastProgress[filename] = longArrayOf(received, total)
        val now = System.currentTimeMillis()
        if (now - lastNotifUpdate >= 800) {
            updateNotification(false)
        }
    }

    private fun ensureForeground() {
        try {
            startInForeground("Preparing download…", -1, 0)
        } catch (_: Exception) {}
    }

    private fun startInForeground(text: String, progress: Int, max: Int) {
        val notification = buildNotification(text, progress, max)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, notification)
        }
        lastNotifUpdate = System.currentTimeMillis()
    }

    private fun updateNotification(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force && now - lastNotifUpdate < 800) return
        lastNotifUpdate = now

        var receivedSum = 0L
        var totalSum = 0L
        var allKnown = true
        synchronized(jobs) {
            for ((name, _) in jobs) {
                val p = lastProgress[name]
                if (p == null || p[1] <= 0) {
                    allKnown = false
                    continue
                }
                receivedSum += p[0]
                totalSum += p[1]
            }
        }
        val count = synchronized(jobs) { jobs.size }
        if (count == 0) return

        if (allKnown && totalSum > 0) {
            val pct = ((receivedSum * 100) / totalSum).toInt().coerceIn(0, 100)
            startInForeground("Downloading $count model(s) • $pct%", pct, 100)
        } else {
            startInForeground("Downloading $count model(s)…", -1, 0)
        }
    }

    private fun buildNotification(text: String, progress: Int, max: Int): android.app.Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            4211,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val pauseIntent = PendingIntent.getService(
            this,
            4212,
            Intent(this, ModelDownloadService::class.java).setAction(ACTION_PAUSE_ALL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val cancelIntent = PendingIntent.getService(
            this,
            4213,
            Intent(this, ModelDownloadService::class.java).setAction(ACTION_CANCEL_ALL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("CubicLM model download")
            .setContentText(text)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(0, "Pause", pauseIntent)
            .addAction(0, "Cancel", cancelIntent)

        if (progress >= 0 && max > 0) {
            builder.setProgress(max, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Model downloads",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Background AI model downloads"
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
