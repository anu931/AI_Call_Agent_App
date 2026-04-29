package com.example.crm_app

import android.app.*
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class CallMonitorService : Service() {

    companion object {
        private const val TAG = "CallMonitorService"
        const val ACTION_START_RECORDING  = "ACTION_START_RECORDING"
        const val ACTION_CANCEL_RECORDING = "ACTION_CANCEL_RECORDING"
        const val ACTION_STOP_RECORDING   = "ACTION_STOP_RECORDING"
        const val ACTION_INIT             = "ACTION_INIT"
        const val EXTRA_PHONE_NUMBER      = "phone_number"
        const val EXTRA_IS_INCOMING       = "is_incoming"
        const val EXTRA_DURATION          = "duration"
        private const val CHANNEL_ID      = "call_monitor_channel"
        private const val NOTIF_ID        = 1001

        // ← Change to your backend IP/port
        private const val BACKEND_BASE    = "http://192.168.1.3:8000"
    }

    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingPath: String? = null
    private var currentPhoneNumber: String?   = null
    private var isRecording = false
    private lateinit var dbHelper: CallLogDbHelper
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onCreate() {
        super.onCreate()
        dbHelper = CallLogDbHelper(this)
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("CRM: Monitoring calls…"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_INIT -> Log.d(TAG, "Service init")

            ACTION_START_RECORDING -> {
                val number     = intent.getStringExtra(EXTRA_PHONE_NUMBER) ?: "Unknown"
                val isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, true)
                currentPhoneNumber = number
                startRecording(number, isIncoming)
            }

            ACTION_STOP_RECORDING -> {
                val number     = intent.getStringExtra(EXTRA_PHONE_NUMBER) ?: currentPhoneNumber ?: "Unknown"
                val duration   = intent.getIntExtra(EXTRA_DURATION, 0)
                val isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, true)
                stopAndSave(number, duration, isIncoming)
            }

            ACTION_CANCEL_RECORDING -> cancelRecording()
        }
        return START_STICKY
    }

    // ─── recording ────────────────────────────────────────────────────────────

    private fun startRecording(phoneNumber: String, isIncoming: Boolean) {
        if (isRecording) return
        try {
            val dir = File(getExternalFilesDir(null), "recordings").also { if (!it.exists()) it.mkdirs() }
            val ts  = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            currentRecordingPath = File(dir, "CALL_${ts}_${phoneNumber.replace("+", "")}.m4a").absolutePath

            mediaRecorder = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                MediaRecorder(this) else @Suppress("DEPRECATION") MediaRecorder()).apply {
                setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(44100)
                setAudioEncodingBitRate(128000)
                setOutputFile(currentRecordingPath)
                prepare()
                start()
            }
            isRecording = true
            updateNotification("CRM: Recording — $phoneNumber")
            Log.d(TAG, "Recording started: $currentRecordingPath")
        } catch (e: Exception) {
            Log.e(TAG, "Start recording failed: ${e.message}")
            mediaRecorder?.release(); mediaRecorder = null; isRecording = false
        }
    }

    private fun stopAndSave(phoneNumber: String, duration: Int, isIncoming: Boolean) {
        val savedPath = if (isRecording) {
            try {
                mediaRecorder?.stop(); mediaRecorder?.release(); mediaRecorder = null
                isRecording = false
                currentRecordingPath
            } catch (e: Exception) {
                Log.e(TAG, "Stop error: ${e.message}")
                mediaRecorder?.release(); mediaRecorder = null; isRecording = false
                null
            }
        } else null

        // Save to local DB
        saveCallLog(phoneNumber, duration, isIncoming, savedPath ?: "")

        // Upload to backend and trigger AI pipeline
        if (!savedPath.isNullOrEmpty()) {
            serviceScope.launch {
                uploadRecording(savedPath, phoneNumber, duration, isIncoming)
            }
        }

        updateNotification("CRM: Monitoring calls…")
    }

    private fun cancelRecording() {
        if (isRecording) {
            try {
                mediaRecorder?.stop()
                mediaRecorder?.release()
                mediaRecorder = null
                isRecording = false
                currentRecordingPath?.let { File(it).delete() }
                currentRecordingPath = null
                Log.d(TAG, "Recording cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Cancel error: ${e.message}")
                mediaRecorder?.release(); mediaRecorder = null; isRecording = false
            }
        }
        updateNotification("CRM: Monitoring calls…")
    }

    // ─── upload .m4a to backend ───────────────────────────────────────────────

    private fun uploadRecording(filePath: String, number: String, duration: Int, isIncoming: Boolean) {
        val file = File(filePath)
        if (!file.exists()) {
            Log.w(TAG, "Upload skipped — file missing: $filePath")
            return
        }
        try {
            val client = OkHttpClient()
            val body = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("number", number)
                .addFormDataPart("duration", duration.toString())
                .addFormDataPart("is_incoming", if (isIncoming) "1" else "0")
                .addFormDataPart(
                    "file",
                    file.name,
                    file.asRequestBody("audio/mp4".toMediaTypeOrNull())
                )
                .build()

            val request = Request.Builder()
                .url("$BACKEND_BASE/calls/upload")
                .post(body)
                .build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                Log.d(TAG, "Upload OK for $number: ${response.body?.string()}")
            } else {
                Log.e(TAG, "Upload failed: ${response.code} ${response.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Upload exception: ${e.message}")
        }
    }

    // ─── local DB ────────────────────────────────────────────────────────────

    private fun saveCallLog(phoneNumber: String, duration: Int, isIncoming: Boolean, recordingPath: String) {
        try {
            val db = dbHelper.writableDatabase
            db.insert("call_logs", null, ContentValues().apply {
                put("phone_number",   phoneNumber)
                put("call_time",      System.currentTimeMillis())
                put("duration",       duration)
                put("is_incoming",    if (isIncoming) 1 else 0)
                put("recording_path", recordingPath)
            })
            db.close()
            Log.d(TAG, "Local log saved for $phoneNumber")
        } catch (e: Exception) {
            Log.e(TAG, "DB save failed: ${e.message}")
        }
    }

    // ─── notifications ────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Call Monitor", NotificationManager.IMPORTANCE_LOW)
                .apply { setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("CRM App")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun updateNotification(text: String) =
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIF_ID, buildNotification(text))

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        if (isRecording) try { mediaRecorder?.stop(); mediaRecorder?.release() } catch (_: Exception) {}
    }
}

class CallLogDbHelper(context: Context) :
    SQLiteOpenHelper(context, "crm_calls.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS call_logs (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                phone_number     TEXT    NOT NULL,
                call_time        INTEGER NOT NULL,
                duration         INTEGER DEFAULT 0,
                is_incoming      INTEGER DEFAULT 1,
                recording_path   TEXT    DEFAULT ''
            )
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS call_logs")
        onCreate(db)
    }
}
