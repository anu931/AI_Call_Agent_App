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
import java.util.concurrent.TimeUnit

class CallMonitorService : Service() {

    companion object {
        private const val TAG            = "CallMonitorService"
        const val ACTION_START_RECORDING  = "ACTION_START_RECORDING"
        const val ACTION_CANCEL_RECORDING = "ACTION_CANCEL_RECORDING"
        const val ACTION_STOP_RECORDING   = "ACTION_STOP_RECORDING"
        const val ACTION_INIT             = "ACTION_INIT"
        const val EXTRA_PHONE_NUMBER      = "phone_number"
        const val EXTRA_IS_INCOMING       = "is_incoming"
        const val EXTRA_DURATION          = "duration"
        private const val CHANNEL_ID      = "call_monitor_channel"
        private const val NOTIF_ID        = 1001
        private const val BACKEND_BASE    = "http://192.168.1.6:8000"
        private const val MIN_VALID_BYTES = 8192L  // 8KB minimum for a real recording
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
            ACTION_INIT            -> Log.d(TAG, "Service initialised")
            ACTION_START_RECORDING -> {
                val number     = intent.getStringExtra(EXTRA_PHONE_NUMBER) ?: "Unknown"
                val isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, true)
                currentPhoneNumber = number
                startRecording(number, isIncoming)
            }
            ACTION_STOP_RECORDING  -> {
                val number     = intent.getStringExtra(EXTRA_PHONE_NUMBER) ?: currentPhoneNumber ?: "Unknown"
                val duration   = intent.getIntExtra(EXTRA_DURATION, 0)
                val isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, true)
                stopAndSave(number, duration, isIncoming)
            }
            ACTION_CANCEL_RECORDING -> cancelRecording()
        }
        return START_STICKY
    }

    // ─── Recording ────────────────────────────────────────────────────────────

    private fun startRecording(phoneNumber: String, isIncoming: Boolean) {
        if (isRecording) return

        try {
            val dir = File(getExternalFilesDir(null), "recordings").also {
                if (!it.exists()) it.mkdirs()
            }
            val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            currentRecordingPath = File(
                dir, "CALL_${ts}_${phoneNumber.replace("+", "")}.wav"
            ).absolutePath

            // ── Audio source priority order ───────────────────────────────────
            //
            // VOICE_CALL is intentionally excluded — on Android 10+ it silently
            // writes an empty file without throwing any error. Useless without root.
            //
            // UNPROCESSED (Android 7+):
            //   Raw microphone signal before any DSP processing. Bypasses noise
            //   cancellation and echo suppression — gives best chance of picking up
            //   acoustic bleed from the earpiece into the microphone. On most
            //   Qualcomm/MediaTek chipsets this is the best option for call capture.
            //
            // VOICE_RECOGNITION:
            //   Tuned for clear speech. Low noise suppression. Works on virtually
            //   all Android versions and devices. Good fallback.
            //
            // MIC:
            //   Standard microphone input. Universal — works everywhere.
            //
            // DEFAULT:
            //   OS decides. Last resort if everything else fails.
            //
            val audioSources = buildList {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    add(MediaRecorder.AudioSource.UNPROCESSED)
                }
                add(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                add(MediaRecorder.AudioSource.MIC)
                add(MediaRecorder.AudioSource.DEFAULT)
            }

            var recorderStarted = false
            var successSource   = -1

            for (source in audioSources) {
                try {
                    val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                        MediaRecorder(this)
                    else
                        @Suppress("DEPRECATION") MediaRecorder()

                    recorder.apply {
                        setAudioSource(source)

                        // WAV output: OutputFormat.DEFAULT + AudioEncoder.DEFAULT
                        // = uncompressed PCM on most devices. No lossy compression,
                        // which gives Whisper the cleanest possible audio input.
                        setOutputFormat(MediaRecorder.OutputFormat.DEFAULT)
                        setAudioEncoder(MediaRecorder.AudioEncoder.DEFAULT)
                        setAudioSamplingRate(16000)   // 16kHz — Whisper's native rate
                        setAudioEncodingBitRate(256000)
                        setAudioChannels(1)            // Mono — sufficient for voice
                        setOutputFile(currentRecordingPath)
                        prepare()
                        start()
                    }

                    mediaRecorder   = recorder
                    isRecording     = true
                    recorderStarted = true
                    successSource   = source
                    Log.d(TAG, "Recording started | source=$source | path=$currentRecordingPath")
                    break

                } catch (e: Exception) {
                    Log.w(TAG, "Source $source failed: ${e.message} — trying next")
                    try { mediaRecorder?.release() } catch (_: Exception) {}
                    mediaRecorder = null
                }
            }

            if (recorderStarted) {
                // Hint user to use speakerphone if we fell back to basic MIC/DEFAULT,
                // since earpiece audio won't bleed into the mic on those sources.
                val hint = when (successSource) {
                    MediaRecorder.AudioSource.MIC,
                    MediaRecorder.AudioSource.DEFAULT ->
                        "Use speakerphone for both voices"
                    else ->
                        "Recording call…"
                }
                updateNotification("CRM: $hint — $phoneNumber")
            } else {
                Log.e(TAG, "All audio sources failed — no recording possible")
                isRecording = false
                updateNotification("CRM: Monitoring — $phoneNumber")
            }

        } catch (e: Exception) {
            Log.e(TAG, "startRecording failed: ${e.message}")
            mediaRecorder?.release()
            mediaRecorder = null
            isRecording   = false
        }
    }

    private fun stopAndSave(phoneNumber: String, duration: Int, isIncoming: Boolean) {
        val rawPath = if (isRecording) {
            try {
                mediaRecorder?.stop()
                mediaRecorder?.release()
                mediaRecorder = null
                isRecording   = false
                currentRecordingPath
            } catch (e: Exception) {
                Log.e(TAG, "Stop error: ${e.message}")
                mediaRecorder?.release()
                mediaRecorder = null
                isRecording   = false
                null
            }
        } else null

        // Validate — discard silent/corrupt files before saving or uploading
        val validPath = rawPath?.let { path ->
            val f = File(path)
            when {
                !f.exists() -> {
                    Log.w(TAG, "Recording file missing after stop")
                    null
                }
                f.length() < MIN_VALID_BYTES -> {
                    Log.w(TAG, "Silent recording (${f.length()} bytes) — discarding")
                    f.delete()
                    null
                }
                else -> {
                    Log.d(TAG, "Valid recording saved: ${f.length()} bytes")
                    path
                }
            }
        }

        saveCallLog(phoneNumber, duration, isIncoming, validPath ?: "")

        if (!validPath.isNullOrEmpty()) {
            serviceScope.launch { uploadRecording(validPath, phoneNumber, duration, isIncoming) }
        }

        updateNotification("CRM: Monitoring calls…")
        currentRecordingPath = null
        currentPhoneNumber   = null
    }

    private fun cancelRecording() {
        if (isRecording) {
            try {
                mediaRecorder?.stop()
                mediaRecorder?.release()
                mediaRecorder = null
                isRecording   = false
                currentRecordingPath?.let { File(it).delete() }
                currentRecordingPath = null
                Log.d(TAG, "Recording cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Cancel error: ${e.message}")
                mediaRecorder?.release()
                mediaRecorder = null
                isRecording   = false
            }
        }
        updateNotification("CRM: Monitoring calls…")
    }

    // ─── Upload ───────────────────────────────────────────────────────────────

    private fun uploadRecording(filePath: String, number: String, duration: Int, isIncoming: Boolean) {
        val file = File(filePath)
        if (!file.exists()) { Log.w(TAG, "Upload skipped — file missing"); return }

        try {
            val client = OkHttpClient.Builder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(120, TimeUnit.SECONDS)   // WAV files are larger than m4a
                .readTimeout(60, TimeUnit.SECONDS)
                .build()

            val body = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("number",      number)
                .addFormDataPart("duration",    duration.toString())
                .addFormDataPart("is_incoming", if (isIncoming) "1" else "0")
                .addFormDataPart("file", file.name,
                    file.asRequestBody("audio/wav".toMediaTypeOrNull()))
                .build()

            val response = client.newCall(
                Request.Builder().url("$BACKEND_BASE/calls/upload").post(body).build()
            ).execute()

            if (response.isSuccessful)
                Log.d(TAG, "Upload OK for $number: ${response.body?.string()}")
            else
                Log.e(TAG, "Upload failed: ${response.code} ${response.message}")

        } catch (e: Exception) {
            Log.e(TAG, "Upload exception: ${e.message}")
        }
    }

    // ─── Local DB ─────────────────────────────────────────────────────────────

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
            Log.d(TAG, "Call log saved for $phoneNumber")
        } catch (e: Exception) {
            Log.e(TAG, "DB save failed: ${e.message}")
        }
    }

    // ─── Notifications ────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Call Monitor", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) }
            )
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

// ─── Local SQLite helper ──────────────────────────────────────────────────────

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