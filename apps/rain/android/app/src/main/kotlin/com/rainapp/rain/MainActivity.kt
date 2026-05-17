package com.rainapp.rain

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val saveRequestCode = 9107
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "rain/file_export",
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "saveReceivedFile" -> saveReceivedFile(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun saveReceivedFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingSaveResult != null) {
            result.error("busy", "Another save is already open.", null)
            return
        }

        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName") ?: "rain-file"
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (sourcePath.isNullOrBlank() || !File(sourcePath).exists()) {
            result.error("missing_source", "Received file is not available.", null)
            return
        }

        pendingSaveResult = result
        pendingSourcePath = sourcePath
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        try {
            startActivityForResult(intent, saveRequestCode)
        } catch (error: Exception) {
            clearPendingSave()
            result.error(
                "save_unavailable",
                "Could not save file. Choose another location.",
                error.message,
            )
        }
    }

    @Deprecated("Deprecated in Android Activity API; FlutterActivity still supports it.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != saveRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingSaveResult
        val sourcePath = pendingSourcePath
        if (result == null || sourcePath == null) {
            clearPendingSave()
            return
        }
        val uri: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            clearPendingSave()
            result.success(false)
            return
        }

        Thread {
            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(File(sourcePath)).use { input ->
                        input.copyTo(output, bufferSize = 64 * 1024)
                    }
                } ?: throw IllegalStateException("Could not open destination.")
                runOnUiThread {
                    clearPendingSave()
                    result.success(true)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    clearPendingSave()
                    result.error(
                        "save_failed",
                        "Could not save file. Choose another location.",
                        error.message,
                    )
                }
            }
        }.start()
    }

    private fun clearPendingSave() {
        pendingSaveResult = null
        pendingSourcePath = null
    }
}
