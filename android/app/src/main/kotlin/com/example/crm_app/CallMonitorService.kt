package com.example.crm_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioManager
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
        private const val TAG                = "CallMonitorService"
        const val ACTION_START_RECORDING      = "ACTION_START_RECORDING"
        const val ACTION_CANCEL_RECORDING     = "ACTION_CANCEL_RECORDING"
        const val ACTION_STOP_RECORDING       = "ACTION_STOP_RECORDING"
        const val ACTION_INIT                 = "ACTION_INIT"
        const val EXTRA_PHONE_NUMBER          = "phone_number"
        const val EXTRA_IS_INCOMING           = "is_incoming"
        const val EXTRA_DURATION              = "duration"
        private const val CHANNEL_ID          = "call_monitor_channel"
        private const val NOTIF_ID            = 1001
        private const val BACKEND_BASE        = "http://10.40.6.149:8000"
        private const val MIN_VALID_BYTES     = 8192L
    }

    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingPath: String? = null
    private var currentPhoneNumber: String?   = null
    private var isRecording = false
    private var previousSpeakerState = false
    private var previousAudioMode    = AudioManager.MODE_NORMAL
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onCreate() {
        super.onCreate()
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
                enableSpeakerphone()
                startRecording(number, isIncoming)
            }
            ACTION_STOP_RECORDING  -> {
                val number     = intent.getStringExtra(EXTRA_PHONE_NUMBER) ?: currentPhoneNumber ?: "Unknown"
                val duration   = intent.getIntExtra(EXTRA_DURATION, 0)
                val isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, true)
                stopAndSave(number, duration, isIncoming)
                disableSpeakerphone()
            }
            ACTION_CANCEL_RECORDING -> {
                cancelRecording()
                disableSpeakerphone()
            }
        }
        return START_STICKY
    }

    // ─── Speakerphone ─────────────────────────────────────────────────────────

    private fun enableSpeakerphone() {
        try {
            val audio            = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            previousSpeakerState = audio.isSpeakerphoneOn
            previousAudioMode    = audio.mode
            audio.mode             = AudioManager.MODE_IN_CALL
            audio.isSpeakerphoneOn = true
            Log.d(TAG, "Speakerphone enabled — both voices will be captured")
        } catch (e: Exception) {
            Log.e(TAG, "enableSpeakerphone failed: ${e.message}")
        }
    }

    private fun disableSpeakerphone() {
        try {
            val audio              = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.isSpeakerphoneOn = previousSpeakerState
            audio.mode             = previousAudioMode
            Log.d(TAG, "Speakerphone restored")
        } catch (e: Exception) {
            Log.e(TAG, "disableSpeakerphone failed: ${e.message}")
        }
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

            val audioSources = buildList {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                    add(MediaRecorder.AudioSource.UNPROCESSED)
                add(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                add(MediaRecorder.AudioSource.MIC)
                add(MediaRecorder.AudioSource.DEFAULT)
            }

            var recorderStarted = false

            for (source in audioSources) {
                try {
                    val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                        MediaRecorder(this)
                    else
                        @Suppress("DEPRECATION") MediaRecorder()

                    recorder.apply {
                        setAudioSource(source)
                        setOutputFormat(MediaRecorder.OutputFormat.DEFAULT)
                        setAudioEncoder(MediaRecorder.AudioEncoder.DEFAULT)
                        setAudioSamplingRate(16000)
                        setAudioEncodingBitRate(256000)
                        setAudioChannels(1)
                        setOutputFile(currentRecordingPath)
                        prepare()
                        start()
                    }

                    mediaRecorder   = recorder
                    isRecording     = true
                    recorderStarted = true
                    Log.d(TAG, "Recording started | source=$source | path=$currentRecordingPath")
                    break
                } catch (e: Exception) {
                    Log.w(TAG, "Source $source failed: ${e.message}")
                    try { mediaRecorder?.release() } catch (_: Exception) {}
                    mediaRecorder = null
                }
            }

            if (!recorderStarted) {
                Log.e(TAG, "All audio sources failed")
                isRecording = false
            }

            updateNotification(
                if (recorderStarted) "CRM: Recording (speakerphone on) — $phoneNumber"
                else "CRM: Monitoring — $phoneNumber"
            )

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

        val validPath = rawPath?.let { path ->
            val f = File(path)
            when {
                !f.exists() -> { Log.w(TAG, "File missing"); null }
                f.length() < MIN_VALID_BYTES -> {
                    Log.w(TAG, "Silent recording (${f.length()} bytes) — discarding")
                    f.delete()
                    null
                }
                else -> { Log.d(TAG, "Valid recording: ${f.length()} bytes"); path }
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
                .writeTimeout(120, TimeUnit.SECONDS)
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
                Log.d(TAG, "Upload OK: ${response.body?.string()}")
            else
                Log.e(TAG, "Upload failed: ${response.code} ${response.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Upload exception: ${e.message}")
        }
    }

    // ─── Room DB save ─────────────────────────────────────────────────────────

    private fun saveCallLog(phoneNumber: String, duration: Int, isIncoming: Boolean, recordingPath: String) {
        try {
            val now     = System.currentTimeMillis()
            val dateFmt = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val timeFmt = SimpleDateFormat("HH:mm:ss",  Locale.getDefault())

            val entity = CallLogEntity(
                phoneNumber   = phoneNumber,
                recordingPath = recordingPath,
                duration      = duration,
                callTime      = now,
                isIncoming    = isIncoming,
                date          = dateFmt.format(Date(now)),
                time          = timeFmt.format(Date(now)),
            )

            CallDatabase.getInstance(applicationContext).callLogDao().insert(entity)
            Log.d(TAG, "Call log saved to Room DB for $phoneNumber")
        } catch (e: Exception) {
            Log.e(TAG, "Room DB save failed: ${e.message}")
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
        if (isRecording) try {
            mediaRecorder?.stop()
            mediaRecorder?.release()
        } catch (_: Exception) {}
    }
}