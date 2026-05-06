package com.example.crm_app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — thin bridge between Flutter and Android.
 *
 * Recording + call detection is handled entirely by CallMonitorService
 * (started on boot via BootReceiver, triggered by CallReceiver).
 * MainActivity's only job is to serve the Flutter MethodChannel for
 * reading/deleting call logs stored in the database.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG     = "CRM_MainActivity"
        private const val CHANNEL = "com.example.crm_app/call_logs"

        private val REQUIRED_PERMISSIONS = buildList {
            add(Manifest.permission.READ_PHONE_STATE)
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                add(Manifest.permission.READ_CALL_LOG)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.READ_MEDIA_AUDIO)
            } else {
                @Suppress("DEPRECATION")
                add(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
        }
    }

    // ── Flutter MethodChannel ─────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCallLogs"   -> getCallLogs(result)
                    "deleteCallLog" -> {
                        val id = call.argument<Int>("id") ?: 0
                        deleteCallLog(id, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onResume() {
        super.onResume()
        requestMissingPermissions()
    }

    private fun requestMissingPermissions() {
        val missing = REQUIRED_PERMISSIONS.filter {
            ActivityCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), 0)
            Log.d(TAG, "Requested permissions: $missing")
        }
    }

    // ── Room DB operations (run on IO thread to stay off main thread) ─────────

    private fun getCallLogs(result: MethodChannel.Result) {
        Thread {
            try {
                val dao  = CallDatabase.getInstance(applicationContext).callLogDao()
                val logs = dao.getAll().map { entity ->
                    mapOf(
                        "id"            to entity.id,
                        "phoneNumber"   to entity.phoneNumber,
                        "recordingPath" to entity.recordingPath,
                        "duration"      to entity.duration,
                        "callTime"      to entity.callTime,
                        "isIncoming"    to if (entity.isIncoming) 1 else 0,
                        "date"          to entity.date,
                        "time"          to entity.time,
                    )
                }
                runOnUiThread { result.success(logs) }
            } catch (e: Exception) {
                Log.e(TAG, "getCallLogs failed: ${e.message}")
                runOnUiThread { result.error("DB_ERROR", e.message, null) }
            }
        }.start()
    }

    private fun deleteCallLog(id: Int, result: MethodChannel.Result) {
        Thread {
            try {
                CallDatabase.getInstance(applicationContext).callLogDao().deleteById(id)
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                Log.e(TAG, "deleteCallLog failed: ${e.message}")
                runOnUiThread { result.error("DB_ERROR", e.message, null) }
            }
        }.start()
    }
}