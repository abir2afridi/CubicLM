package com.cubiclm.app

import android.app.AlertDialog
import android.app.AlarmManager
import android.app.DownloadManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread
import kotlin.system.exitProcess
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    private val importChannelName = "com.cubiclm.app/model_import"
    private val importRequestCode = 4207
    private val exportFolderRequestCode = 4208
    private val mainHandler = Handler(Looper.getMainLooper())

    private var importChannel: MethodChannel? = null
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingExportFolderResult: MethodChannel.Result? = null
    private var pendingModelsDir: String? = null
    private var pendingSharedText: String? = null
    private val monitoredInAppDownloads = ConcurrentHashMap.newKeySet<Long>()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    /// Stashes ACTION_SEND text/plain for Dart to pull via getSharedText.
    /// Called from configureFlutterEngine (cold start) and onNewIntent.
    private fun handleShareIntent(intent: Intent?) {
        try {
            if (intent?.action == Intent.ACTION_SEND &&
                intent.type?.startsWith("text/") == true) {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                    ?: intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!text.isNullOrBlank()) pendingSharedText = text
            }
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        handleShareIntent(intent)
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, importChannelName)
        ModelDownloadService.emitter = { filename, copied, total, bps, status ->
            mainHandler.post {
                importChannel?.invokeMethod(
                    "importProgress",
                    mapOf(
                        "filename" to filename,
                        "copiedBytes" to copied,
                        "totalBytes" to total,
                        "bytesPerSecond" to bps,
                        "status" to status,
                    )
                )
            }
        }
        importChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAndImportModel" -> {
                    if (pendingImportResult != null) {
                        result.error("IMPORT_BUSY", "Another model import is already running.", null)
                        return@setMethodCallHandler
                    }
                    val modelsDir = call.argument<String>("modelsDir")
                    if (modelsDir.isNullOrBlank()) {
                        result.error("INVALID_DIR", "Models directory is missing.", null)
                        return@setMethodCallHandler
                    }
                    pendingModelsDir = modelsDir
                    pendingImportResult = result
                    openModelPicker()
                }
                "downloadToDownloads" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    if (url.isNullOrBlank() || filename.isNullOrBlank()) {
                        result.error("INVALID_DOWNLOAD", "Model URL or filename is missing.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val downloadId = enqueueDownloadToDownloads(url, filename)
                        result.success(mapOf("downloadId" to downloadId, "filename" to sanitizeFilename(filename)))
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "cancelDownloadToDownloads" -> {
                    val downloadId = (call.argument<Any>("downloadId") as? Number)?.toLong()
                    if (downloadId != null) {
                        try {
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            manager.remove(downloadId)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CANCEL_FAILED", e.message ?: e.toString(), null)
                        }
                    } else {
                        result.error("INVALID_DOWNLOAD_ID", "Download ID is missing.", null)
                    }
                }
                "saveBytesToDownloads" -> {
                    val filename = call.argument<String>("filename")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val subfolder = sanitizeFilename(call.argument<String>("subfolder") ?: "CubicLM")
                        .ifBlank { "CubicLM" }
                    if (filename.isNullOrBlank() || bytes == null) {
                        result.error("INVALID_EXPORT", "Filename or bytes are missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "save-export") {
                        try {
                            val displayPath = saveBytesToDownloads(sanitizeFilename(filename), bytes, mimeType, subfolder)
                            mainHandler.post { result.success(displayPath) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("SAVE_FAILED", e.message ?: e.toString(), null) }
                        }
                    }
                }
                "pickExportFolder" -> {
                    if (pendingExportFolderResult != null) {
                        result.error("PICKER_BUSY", "A folder picker is already open.", null)
                        return@setMethodCallHandler
                    }
                    pendingExportFolderResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        startActivityForResult(intent, exportFolderRequestCode)
                    } catch (e: Exception) {
                        pendingExportFolderResult = null
                        result.error("NO_FILE_MANAGER", e.message ?: e.toString(), null)
                    }
                }
                "checkTreeFolderAccess" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(treeUri)
                        val ok = contentResolver.persistedUriPermissions.any {
                            it.uri == uri && it.isWritePermission
                        }
                        result.success(ok)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "saveBytesToTreeFolder" -> {
                    val filename = call.argument<String>("filename")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val treeUri = call.argument<String>("treeUri")
                    if (filename.isNullOrBlank() || bytes == null || treeUri.isNullOrBlank()) {
                        result.error("INVALID_EXPORT", "Filename, bytes or folder are missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "save-export-tree") {
                        try {
                            val displayPath = saveBytesToTreeFolder(
                                sanitizeFilename(filename), bytes, mimeType, Uri.parse(treeUri))
                            mainHandler.post { result.success(displayPath) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("SAVE_FAILED", e.message ?: e.toString(), null) }
                        }
                    }
                }
                "downloadModelInApp" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    val modelsDir = call.argument<String>("modelsDir")
                    if (url.isNullOrBlank() || filename.isNullOrBlank() || modelsDir.isNullOrBlank()) {
                        result.error("INVALID_DOWNLOAD", "URL, filename, or modelsDir is missing.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val downloadId = enqueueDownloadInApp(url, filename, modelsDir)
                        result.success(mapOf("downloadId" to downloadId, "filename" to sanitizeFilename(filename)))
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "cancelDownloadInApp" -> {
                    val downloadId = (call.argument<Any>("downloadId") as? Number)?.toLong()
                    if (downloadId != null) {
                        try {
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            manager.remove(downloadId)
                            removeInAppDownload(downloadId)
                            val filename = call.argument<String>("filename")
                            if (!filename.isNullOrBlank()) {
                                val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), sanitizeFilename(filename))
                                if (destFile.exists()) destFile.delete()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CANCEL_FAILED", e.message ?: e.toString(), null)
                        }
                    } else {
                        result.error("INVALID_DOWNLOAD_ID", "Download ID is missing.", null)
                    }
                }
                "getActiveDownloads" -> {
                    thread(name = "download-inapp-reconcile") {
                        try {
                            val activeList = reconcileInAppDownloads()
                            mainHandler.post { result.success(activeList) }
                        } catch (e: java.lang.Exception) {
                            mainHandler.post {
                                result.error("QUERY_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "startStreamDownload" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    val modelsDir = call.argument<String>("modelsDir")
                    if (url.isNullOrBlank() || filename.isNullOrBlank() || modelsDir.isNullOrBlank()) {
                        result.error("INVALID_DOWNLOAD", "URL, filename, or modelsDir is missing.", null)
                        return@setMethodCallHandler
                    }
                    val started = ModelDownloadService.startJob(this, url, filename, modelsDir)
                    if (started != null) {
                        result.success(mapOf("filename" to started))
                    } else {
                        result.error("DOWNLOAD_BUSY", "This model is already downloading.", null)
                    }
                }
                "pauseStreamDownload" -> {
                    val filename = call.argument<String>("filename")
                    if (!filename.isNullOrBlank()) {
                        ModelDownloadService.pauseJob(ModelDownloadService.sanitize(filename))
                        result.success(true)
                    } else {
                        result.error("INVALID_FILENAME", "Filename is missing.", null)
                    }
                }
                "cancelStreamDownload" -> {
                    val filename = call.argument<String>("filename")
                    if (!filename.isNullOrBlank()) {
                        ModelDownloadService.cancelJob(ModelDownloadService.sanitize(filename))
                        result.success(true)
                    } else {
                        result.error("INVALID_FILENAME", "Filename is missing.", null)
                    }
                }
                "getStreamDownloads" -> {
                    thread(name = "stream-download-snapshot") {
                        try {
                            val list = ModelDownloadService.persistedSnapshot(this)
                            mainHandler.post { result.success(list) }
                        } catch (e: java.lang.Exception) {
                            mainHandler.post {
                                result.error("QUERY_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "restartApp" -> {
                    restartApp()
                    result.success(null)
                }
                "setSecureFlag" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setSecureFlag(enabled)
                    result.success(null)
                }
                "getSharedText" -> {
                    val text = pendingSharedText
                    pendingSharedText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }

    }

    /// Hides app content from Recents screenshots / screen capture while
    /// App Lock is armed. Called from Dart via setSecureFlag.
    private fun setSecureFlag(enabled: Boolean) {
        try {
            if (enabled) {
                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
            }
        } catch (e: Exception) {
            Log.w("CubicLM", "setSecureFlag failed: ${e.message}")
        }
    }

    /// Writes export bytes into Download/<subfolder> without any picker
    /// dialog (MediaStore on API 29+, direct write below). No storage
    /// permission needed on modern Android. Returns a display path.
    private fun saveBytesToDownloads(
        filename: String,
        bytes: ByteArray,
        mimeType: String,
        subfolder: String,
    ): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/$subfolder"
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: throw Exception("MediaStore refused the file")
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw Exception("Could not open output stream")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                try {
                    contentResolver.delete(uri, null, null)
                } catch (_: Exception) {
                }
                throw e
            }
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                ),
                subfolder
            )
            if (!dir.exists() && !dir.mkdirs()) {
                throw Exception("Could not create $subfolder")
            }
            File(dir, filename).writeBytes(bytes)
        }
        return "Download/$subfolder/$filename"
    }

    /// Writes export bytes into a user-picked Storage Access Framework
    /// folder (ACTION_OPEN_DOCUMENT_TREE + persistable permission). Works
    /// on every Android version with no storage permission. Returns a
    /// display path for the success snackbar.
    private fun saveBytesToTreeFolder(
        filename: String,
        bytes: ByteArray,
        mimeType: String,
        treeUri: android.net.Uri,
    ): String {
        val docUri = DocumentsContract.createDocument(
            contentResolver, treeUri, mimeType, filename
        ) ?: throw Exception("Could not create file in the picked folder")
        try {
            contentResolver.openOutputStream(docUri)?.use { it.write(bytes) }
                ?: throw Exception("Could not open output stream")
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(contentResolver, docUri)
            } catch (_: Exception) {
            }
            throw e
        }
        return "${treeDisplayName(treeUri)}/$filename"
    }

    /// Human name of a picked tree (e.g. "MyExports"), "Downloads" style
    /// fallback when the provider won't say.
    private fun treeDisplayName(treeUri: android.net.Uri): String {
        try {
            contentResolver.query(
                treeUri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val name = c.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (_: Exception) {
        }
        return treeUri.lastPathSegment
            ?.substringAfterLast(':')
            ?.substringAfterLast('/')
            ?.ifBlank { "Picked folder" }
            ?: "Picked folder"
    }

    private fun restartApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent == null) {
            finishAffinity()
            return
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        val pendingIntent = PendingIntent.getActivity(
            this,
            9208,
            launchIntent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.set(
            AlarmManager.RTC,
            System.currentTimeMillis() + 350L,
            pendingIntent
        )
        finishAffinity()
        exitProcess(0)
    }

    private fun enqueueDownloadToDownloads(url: String, filename: String): Long {
        val safeName = sanitizeFilename(filename)
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle(safeName)
            setDescription("Downloading AI model")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, safeName)
            addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
            addRequestHeader("Accept", "*/*")
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = manager.enqueue(request)

        thread(name = "download-monitor-$downloadId") {
            var isFinished = false
            var lastBytes = 0L
            var lastTime = System.currentTimeMillis()
            var lastReportedSpeed = 0.0

            while (!isFinished) {
                Thread.sleep(1000)
                val query = DownloadManager.Query().setFilterById(downloadId)
                manager.query(query)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                        val bytesDownloadedIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                        val bytesTotalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)

                        if (statusIndex >= 0 && bytesDownloadedIndex >= 0 && bytesTotalIndex >= 0) {
                            val status = cursor.getInt(statusIndex)
                            val downloaded = cursor.getLong(bytesDownloadedIndex)
                            val total = cursor.getLong(bytesTotalIndex)

                            val now = System.currentTimeMillis()
                            val elapsedSeconds = (now - lastTime) / 1000.0
                            var bytesPerSecond = 0.0

                            if (downloaded > lastBytes) {
                                bytesPerSecond = if (elapsedSeconds > 0) ((downloaded - lastBytes) / elapsedSeconds) else 0.0
                                lastBytes = downloaded
                                lastTime = now
                                lastReportedSpeed = bytesPerSecond
                            } else {
                                if (elapsedSeconds > 3.0) {
                                    lastReportedSpeed = 0.0
                                }
                                bytesPerSecond = lastReportedSpeed
                            }

                            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                                isFinished = true
                                emitProgress(safeName, total, total, 0.0, "Download complete")
                            } else if (status == DownloadManager.STATUS_FAILED) {
                                isFinished = true
                                emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                            } else {
                                emitProgress(safeName, downloaded, total, bytesPerSecond, "Downloading to phone...")
                            }
                        }
                    } else {
                        isFinished = true
                        emitProgress(safeName, 0, 0, 0.0, "Download cancelled")
                    }
                } ?: run {
                    isFinished = true
                }
            }
        }
        return downloadId
    }

    private fun enqueueDownloadInApp(url: String, filename: String, modelsDir: String): Long {
        val safeName = sanitizeFilename(filename)
        val tempDownloadsDir = File(getExternalFilesDir(null), "temp_downloads")
        tempDownloadsDir.mkdirs()
        val destFile = File(tempDownloadsDir, safeName)
        if (destFile.exists()) destFile.delete()

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle(safeName)
            setDescription("Downloading local AI model")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            setDestinationUri(Uri.fromFile(destFile))
            addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
            addRequestHeader("Accept", "*/*")
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = manager.enqueue(request)
        persistInAppDownload(downloadId, safeName, modelsDir)
        monitorInAppDownload(downloadId, safeName, modelsDir)
        return downloadId
    }

    private fun monitorInAppDownload(downloadId: Long, safeName: String, modelsDir: String) {
        if (!monitoredInAppDownloads.add(downloadId)) return
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), safeName)
        thread(name = "download-inapp-monitor-$downloadId") {
            var isFinished = false
            var lastBytes = 0L
            var lastTime = System.currentTimeMillis()
            var lastReportedSpeed = 0.0

            while (!isFinished) {
                Thread.sleep(1000)
                val query = DownloadManager.Query().setFilterById(downloadId)
                manager.query(query)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                        val bytesDownloadedIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                        val bytesTotalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)

                        if (statusIndex >= 0 && bytesDownloadedIndex >= 0 && bytesTotalIndex >= 0) {
                            val status = cursor.getInt(statusIndex)
                            val downloaded = cursor.getLong(bytesDownloadedIndex)
                            val total = cursor.getLong(bytesTotalIndex)

                            val now = System.currentTimeMillis()
                            val elapsedSeconds = (now - lastTime) / 1000.0
                            var bytesPerSecond = 0.0

                            if (downloaded > lastBytes) {
                                bytesPerSecond = if (elapsedSeconds > 0) ((downloaded - lastBytes) / elapsedSeconds) else 0.0
                                lastBytes = downloaded
                                lastTime = now
                                lastReportedSpeed = bytesPerSecond
                            } else {
                                if (elapsedSeconds > 3.0) {
                                    lastReportedSpeed = 0.0
                                }
                                bytesPerSecond = lastReportedSpeed
                            }

                            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                                isFinished = true
                                finalizeInAppDownload(downloadId, safeName, modelsDir, downloaded, total)
                            } else if (status == DownloadManager.STATUS_FAILED) {
                                isFinished = true
                                removeInAppDownload(downloadId)
                                emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                            } else {
                                emitProgress(safeName, downloaded, total, bytesPerSecond, "Downloading...")
                            }
                        }
                    } else {
                        isFinished = true
                        removeInAppDownload(downloadId)
                        emitProgress(safeName, 0, 0, 0.0, "Download cancelled")
                    }
                } ?: run {
                    isFinished = true
                }
            }
            monitoredInAppDownloads.remove(downloadId)
        }
    }

    private fun finalizeInAppDownload(
        downloadId: Long,
        safeName: String,
        modelsDir: String,
        downloaded: Long,
        total: Long,
    ) {
        val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), safeName)
        try {
            emitProgress(safeName, downloaded, total, 0.0, "Importing to app storage...")
            val targetFile = File(modelsDir, safeName)
            targetFile.parentFile?.mkdirs()
            val partFile = File(targetFile.parentFile, "${targetFile.name}.part")
            if (partFile.exists()) partFile.delete()
            if (!destFile.exists()) {
                if (targetFile.exists() && targetFile.length() > 0L) {
                    removeInAppDownload(downloadId)
                    emitProgress(safeName, total, total, 0.0, "Download complete")
                    return
                }
                throw IllegalStateException("Downloaded temporary file is missing.")
            }
            destFile.copyTo(partFile, overwrite = true)
            if (targetFile.exists()) targetFile.delete()
            if (!partFile.renameTo(targetFile)) {
                throw IllegalStateException("Unable to finalize downloaded model.")
            }
            destFile.delete()
            removeInAppDownload(downloadId)
            emitProgress(safeName, total, total, 0.0, "Download complete")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to import downloaded model: ${e.message}", e)
            emitProgress(safeName, downloaded, total, 0.0, "Download failed: import error")
        }
    }

    private fun persistInAppDownload(downloadId: Long, filename: String, modelsDir: String) {
        val record = JSONObject()
            .put("filename", filename)
            .put("modelsDir", modelsDir)
        getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
            .edit()
            .putString(downloadId.toString(), record.toString())
            .apply()
    }

    private fun removeInAppDownload(downloadId: Long) {
        getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
            .edit()
            .remove(downloadId.toString())
            .apply()
    }

    private fun reconcileInAppDownloads(): List<Map<String, Any>> {
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val preferences = getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
        val activeList = mutableListOf<Map<String, Any>>()
        for ((idText, rawRecord) in preferences.all) {
            val downloadId = idText.toLongOrNull() ?: continue
            val record = runCatching { JSONObject(rawRecord as String) }.getOrNull() ?: continue
            val safeName = record.optString("filename")
            val modelsDir = record.optString("modelsDir")
            if (safeName.isBlank() || modelsDir.isBlank()) {
                removeInAppDownload(downloadId)
                continue
            }
            manager.query(DownloadManager.Query().setFilterById(downloadId))?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    removeInAppDownload(downloadId)
                    return@use
                }
                val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                when (status) {
                    DownloadManager.STATUS_SUCCESSFUL ->
                        finalizeInAppDownload(downloadId, safeName, modelsDir, downloaded, total)
                    DownloadManager.STATUS_FAILED -> {
                        removeInAppDownload(downloadId)
                        emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                    }
                    else -> {
                        val statusText = when (status) {
                            DownloadManager.STATUS_PAUSED -> "Paused"
                            DownloadManager.STATUS_PENDING -> "Pending"
                            else -> "Downloading..."
                        }
                        activeList.add(mapOf(
                            "downloadId" to downloadId,
                            "filename" to safeName,
                            "downloaded" to downloaded,
                            "total" to total,
                            "status" to statusText,
                        ))
                        monitorInAppDownload(downloadId, safeName, modelsDir)
                    }
                }
            }
        }
        return activeList
    }

    private fun openModelPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, importRequestCode)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == exportFolderRequestCode) {
            val pending = pendingExportFolderResult
            pendingExportFolderResult = null
            if (pending == null) return
            if (resultCode != RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }
            val treeUri = data.data!!
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (e: Exception) {
                pending.error("PERMISSION_DENIED", e.message ?: e.toString(), null)
                return
            }
            pending.success(mapOf(
                "uri" to treeUri.toString(),
                "name" to treeDisplayName(treeUri),
            ))
            return
        }
        if (requestCode != importRequestCode) return

        if (resultCode != RESULT_OK || data?.data == null) {
            finishImportSuccess(mapOf("cancelled" to true))
            return
        }

        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Some providers do not allow persistable grants; the one-shot grant is enough here.
        }

        val filename = displayNameFor(uri)
        val lower = filename.lowercase()
        if (!lower.endsWith(".gguf") && !lower.endsWith(".litertlm") && !lower.endsWith(".safetensors")) {
            finishImportError(
                "UNSUPPORTED_MODEL",
                "Only .gguf, .litertlm, and .safetensors files can be imported."
            )
            return
        }

        val size = sizeFor(uri)
        if (size <= 0L) {
            finishImportError("EMPTY_MODEL", "The selected file is empty or unreadable.")
            return
        }

        val modelsDir = pendingModelsDir
        if (modelsDir.isNullOrBlank()) {
            finishImportError("INVALID_DIR", "Models directory is missing.")
            return
        }

        val destination = File(modelsDir, sanitizeFilename(filename))
        if (destination.exists()) {
            AlertDialog.Builder(this)
                .setTitle("Model already imported")
                .setMessage("${destination.name} already exists in app storage. Replace it?")
                .setNegativeButton("Cancel") { _, _ ->
                    finishImportSuccess(mapOf("cancelled" to true))
                }
                .setPositiveButton("Replace") { _, _ ->
                    copyUriToModel(uri, destination, size, true)
                }
                .show()
        } else {
            copyUriToModel(uri, destination, size, false)
        }
    }

    private fun copyUriToModel(uri: Uri, destination: File, totalBytes: Long, replacing: Boolean) {
        emitProgress(destination.name, 0L, totalBytes, 0.0, "Copying to app storage...")
        thread(name = "model-import-${destination.name}") {
            val partFile = File(destination.parentFile, "${destination.name}.part")
            val startedAt = System.currentTimeMillis()
            var copied = 0L
            try {
                destination.parentFile?.mkdirs()
                if (partFile.exists()) partFile.delete()

                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) {
                        throw IllegalStateException("Unable to open selected file.")
                    }
                    partFile.outputStream().use { output ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                            copied += read
                            val elapsedSeconds =
                                (System.currentTimeMillis() - startedAt).coerceAtLeast(1) / 1000.0
                            emitProgress(
                                destination.name,
                                copied,
                                totalBytes,
                                copied / elapsedSeconds,
                                "Copying to app storage..."
                            )
                        }
                    }
                }

                if (replacing && destination.exists()) destination.delete()
                if (!partFile.renameTo(destination)) {
                    throw IllegalStateException("Unable to finalize imported model.")
                }
                emitProgress(destination.name, totalBytes, totalBytes, 0.0, "Import complete")
                finishImportSuccess(
                    mapOf(
                        "cancelled" to false,
                        "filename" to destination.name,
                        "bytes" to totalBytes,
                        "replaced" to replacing
                    )
                )
            } catch (e: Exception) {
                if (partFile.exists()) partFile.delete()
                finishImportError("IMPORT_FAILED", e.message ?: e.toString())
            }
        }
    }

    private fun emitProgress(
        filename: String,
        copiedBytes: Long,
        totalBytes: Long,
        bytesPerSecond: Double,
        status: String,
    ) {
        mainHandler.post {
            importChannel?.invokeMethod(
                "importProgress",
                mapOf(
                    "filename" to filename,
                    "copiedBytes" to copiedBytes,
                    "totalBytes" to totalBytes,
                    "bytesPerSecond" to bytesPerSecond,
                    "status" to status
                )
            )
        }
    }

    private fun finishImportSuccess(payload: Map<String, Any?>) {
        mainHandler.post {
            pendingImportResult?.success(payload)
            pendingImportResult = null
            pendingModelsDir = null
        }
    }

    private fun finishImportError(code: String, message: String) {
        mainHandler.post {
            pendingImportResult?.error(code, message, null)
            pendingImportResult = null
            pendingModelsDir = null
        }
    }

    private fun displayNameFor(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        val value = cursor.getString(index)
                        if (!value.isNullOrBlank()) return value
                    }
                }
            }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "model.gguf"
    }

    private fun sizeFor(uri: Uri): Long {
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (index >= 0) return cursor.getLong(index)
                }
            }
        return -1L
    }

    private fun sanitizeFilename(filename: String): String {
        return filename.replace(Regex("""[\\/:*?"<>|]"""), "_")
    }
}
