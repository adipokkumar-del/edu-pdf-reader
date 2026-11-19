package com.edu.edu_pdf_reader

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.content.FileProvider
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var pendingPath: String? = null
    private var pickResult: MethodChannel.Result? = null
    private val pickRequest = 4711

    private val nativePrefs by lazy {
        getSharedPreferences("edu_native", Context.MODE_PRIVATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingPath = resolvePdf(intent)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "edu_pdf/native")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPdf" -> {
                    result.success(pendingPath)
                    pendingPath = null
                }
                "hasDndAccess" ->
                    result.success(notificationManager().isNotificationPolicyAccessGranted)
                "openDndSettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    } catch (e: Exception) {
                        // Settings screen not available on this device.
                    }
                    result.success(null)
                }
                "setMute" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        result.success(enableDnd())
                    } else {
                        restoreDnd()
                        result.success(true)
                    }
                }
                "syncReminders" -> {
                    Reminders.sync(this, call.argument<String>("json") ?: "[]")
                    result.success(true)
                }
                "pickFile" -> {
                    if (pickResult != null) {
                        result.success(null)
                    } else {
                        val pick = Intent(Intent.ACTION_OPEN_DOCUMENT)
                        pick.addCategory(Intent.CATEGORY_OPENABLE)
                        pick.type = "*/*"
                        pickResult = result
                        try {
                            startActivityForResult(pick, pickRequest)
                        } catch (e: Exception) {
                            pickResult = null
                            result.success(null)
                        }
                    }
                }
                "saveToDownloads" -> {
                    val src = call.argument<String>("path")
                    val name = call.argument<String>("name")
                    val mime = call.argument<String>("mime") ?: "application/pdf"
                    result.success(
                        if (src != null && name != null) saveToDownloads(File(src), name, mime) else null
                    )
                }
                "defaultPdfState" -> result.success(defaultPdfState())
                "chooseDefaultPdf" -> {
                    val path = call.argument<String>("path")
                    result.success(path != null && launchViewer(File(path)))
                }
                "openDefaultAppsSettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    } catch (e: Exception) {
                        // Settings screen not available on this device.
                    }
                    result.success(null)
                }
                "setSecure" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "canExactAlarms" -> result.success(Reminders.canExact(this))
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= 31) {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (e: Exception) {
                            // Settings screen not available on this device.
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickRequest) {
            val pending = pickResult
            pickResult = null
            var path: String? = null
            val uri = data?.data
            if (resultCode == RESULT_OK && uri != null) {
                path = try {
                    materialize(uri)
                } catch (e: Exception) {
                    null
                }
            }
            pending?.success(path)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val path = resolvePdf(intent)
        if (path != null && ::channel.isInitialized) {
            channel.invokeMethod("openPdf", path)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    /** Asks for the highest refresh rate the screen offers at its current size. */
    @Suppress("DEPRECATION")
    private fun requestHighRefreshRate() {
        try {
            val display = windowManager.defaultDisplay
            val current = display.mode
            var best = current
            for (mode in display.supportedModes) {
                if (mode.physicalWidth == current.physicalWidth &&
                    mode.physicalHeight == current.physicalHeight &&
                    mode.refreshRate > best.refreshRate
                ) {
                    best = mode
                }
            }
            if (best.modeId != current.modeId) {
                val attributes = window.attributes
                attributes.preferredDisplayModeId = best.modeId
                window.attributes = attributes
            }
        } catch (e: Exception) {
            // Keep the system default.
        }
    }

    /** Copies a file into Downloads/EduPDF. Returns a readable location, or null. */
    private fun saveToDownloads(src: File, name: String, mime: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= 29) {
                val values = ContentValues()
                values.put(MediaStore.Downloads.DISPLAY_NAME, name)
                values.put(MediaStore.Downloads.MIME_TYPE, mime)
                values.put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/EduPDF"
                )
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return null
                val out = contentResolver.openOutputStream(uri) ?: return null
                out.use { sink -> src.inputStream().use { it.copyTo(sink) } }
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "EduPDF"
                )
                dir.mkdirs()
                src.copyTo(File(dir, name), true)
            }
            "Downloads/EduPDF/$name"
        } catch (e: Exception) {
            null
        }
    }

    /** 'self' when this app opens PDFs by default, 'other' for another app, else 'none'. */
    private fun defaultPdfState(): String {
        return try {
            val probe = Intent(Intent.ACTION_VIEW)
            probe.setDataAndType(Uri.parse("content://edupdf.probe/sample.pdf"), "application/pdf")
            val info = packageManager.resolveActivity(probe, PackageManager.MATCH_DEFAULT_ONLY)
            val pkg = info?.activityInfo?.packageName
            when {
                pkg == null -> "none"
                pkg == packageName -> "self"
                pkg == "android" || pkg.contains("resolver") -> "none"
                else -> "other"
            }
        } catch (e: Exception) {
            "none"
        }
    }

    /** Opens a PDF so Android shows its "Open with / Always" chooser. */
    private fun launchViewer(file: File): Boolean {
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val view = Intent(Intent.ACTION_VIEW)
            view.setDataAndType(uri, "application/pdf")
            view.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(view)
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        restoreDnd()
        super.onDestroy()
    }

    // ---- Do Not Disturb -----------------------------------------------------

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /** Remembers the user's own setting first, so we only undo what we changed. */
    private fun enableDnd(): Boolean {
        val manager = notificationManager()
        if (!manager.isNotificationPolicyAccessGranted) return false
        if (!nativePrefs.contains("dnd_prev")) {
            nativePrefs.edit()
                .putInt("dnd_prev", manager.currentInterruptionFilter)
                .apply()
        }
        manager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        return true
    }

    private fun restoreDnd() {
        if (!nativePrefs.contains("dnd_prev")) return
        val manager = notificationManager()
        var previous = nativePrefs.getInt("dnd_prev", NotificationManager.INTERRUPTION_FILTER_ALL)
        if (previous == NotificationManager.INTERRUPTION_FILTER_UNKNOWN) {
            previous = NotificationManager.INTERRUPTION_FILTER_ALL
        }
        if (manager.isNotificationPolicyAccessGranted) {
            manager.setInterruptionFilter(previous)
        }
        nativePrefs.edit().remove("dnd_prev").apply()
    }

    // ---- Incoming PDFs ------------------------------------------------------

    @Suppress("DEPRECATION")
    private fun resolvePdf(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return null
        return try {
            materialize(uri)
        } catch (e: Exception) {
            null
        }
    }

    /** Returns a real file path. content:// documents are copied to the app cache. */
    private fun materialize(uri: Uri): String? {
        if (uri.scheme == "file") {
            val path = uri.path
            if (path != null && File(path).canRead()) return path
        }

        var name = "document.pdf"
        try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        cursor.getString(index)?.let { name = it }
                    }
                }
            }
        } catch (e: Exception) {
            // Keep the default name.
        }

        val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val lower = safe.lowercase()
        val finalName = if (lower.endsWith(".pdf") || lower.endsWith(".edunote")) safe else "$safe.pdf"

        val dir = File(cacheDir, "opened")
        dir.mkdirs()
        val target = File(dir, Integer.toHexString(uri.toString().hashCode()) + "_" + finalName)

        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { source ->
            target.outputStream().use { sink -> source.copyTo(sink) }
        }
        return target.absolutePath
    }
}
