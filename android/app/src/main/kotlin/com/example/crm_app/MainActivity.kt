package com.example.crm_app

import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.crm_app/call_logs"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Start the monitoring service when app opens
        val serviceIntent = Intent(this, CallMonitorService::class.java).apply {
            action = CallMonitorService.ACTION_INIT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCallLogs" -> result.success(getCallLogsFromDb())
                    "deleteCallLog" -> {
                        val id = call.argument<Int>("id")
                        if (id != null) { deleteCallLog(id); result.success(true) }
                        else result.error("INVALID_ARG", "id is required", null)
                    }
                    "insertTestLog" -> { insertTestLog(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getCallLogsFromDb(): List<Map<String, Any?>> {
        val dbHelper = CallLogDbHelper(this)
        val db = dbHelper.readableDatabase
        val logs = mutableListOf<Map<String, Any?>>()
        val cursor: Cursor = db.query("call_logs", null, null, null, null, null, "call_time DESC")
        cursor.use {
            while (it.moveToNext()) {
                logs.add(mapOf(
                    "id"             to it.getInt(it.getColumnIndexOrThrow("id")),
                    "phone_number"   to it.getString(it.getColumnIndexOrThrow("phone_number")),
                    "call_time"      to it.getLong(it.getColumnIndexOrThrow("call_time")),
                    "duration"       to it.getInt(it.getColumnIndexOrThrow("duration")),
                    "is_incoming"    to (it.getInt(it.getColumnIndexOrThrow("is_incoming")) == 1),
                    "recording_path" to it.getString(it.getColumnIndexOrThrow("recording_path"))
                ))
            }
        }
        db.close()
        return logs
    }

    private fun deleteCallLog(id: Int) {
        val dbHelper = CallLogDbHelper(this)
        val db = dbHelper.writableDatabase
        db.delete("call_logs", "id = ?", arrayOf(id.toString()))
        db.close()
    }

    private fun insertTestLog() {
        val dbHelper = CallLogDbHelper(this)
        val db = dbHelper.writableDatabase
        val values = ContentValues().apply {
            put("phone_number", "+91 9876543210")
            put("call_time", System.currentTimeMillis())
            put("duration", 62)
            put("is_incoming", 1)
            put("recording_path", "")
        }
        db.insert("call_logs", null, values)
        db.close()
    }
}
