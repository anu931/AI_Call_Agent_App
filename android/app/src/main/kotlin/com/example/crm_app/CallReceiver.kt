package com.example.crm_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.TelephonyManager
import android.util.Log

class CallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CRM_CALL"

        @Volatile private var lastState   = TelephonyManager.CALL_STATE_IDLE
        @Volatile private var callStart   = 0L
        @Volatile private var isIncoming  = true
        @Volatile private var savedNumber = "Unknown"
        @Volatile private var wasRinging  = false
        @Volatile private var callAnswered = false
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val number   = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        // LOG EVERY RAW EVENT — check logcat to see exactly what fires on rejection
        Log.e(TAG, ">>> RAW STATE=$stateStr | number=$number | lastState=$lastState | wasRinging=$wasRinging | callAnswered=$callAnswered | callStart=$callStart")

        val state = when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
            TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
            else                                  -> TelephonyManager.CALL_STATE_IDLE
        }

        onStateChanged(context, state, number)
        lastState = state
    }

    private fun onStateChanged(context: Context, state: Int, number: String?) {
        when (state) {

            TelephonyManager.CALL_STATE_RINGING -> {
                wasRinging   = true
                callAnswered = false
                callStart    = 0
                isIncoming   = true
                savedNumber  = number ?: "Unknown"
                Log.e(TAG, "RINGING — savedNumber=$savedNumber")
            }

            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (wasRinging) {
                    // Was ringing → now OFFHOOK = incoming answered
                    callAnswered = true
                    Log.e(TAG, "OFFHOOK after RINGING = INCOMING ANSWERED: $savedNumber")
                } else if (lastState == TelephonyManager.CALL_STATE_IDLE) {
                    // No prior ringing = outgoing call
                    callAnswered = true
                    isIncoming   = false
                    savedNumber  = number ?: "Unknown"
                    Log.e(TAG, "OFFHOOK from IDLE = OUTGOING: $savedNumber")
                } else {
                    Log.e(TAG, "OFFHOOK in unexpected state — lastState=$lastState, ignoring")
                }

                if (callAnswered) {
                    callStart = System.currentTimeMillis()
                    startService(context, savedNumber, isIncoming)
                }
            }

            TelephonyManager.CALL_STATE_IDLE -> {
                Log.e(TAG, "IDLE — callAnswered=$callAnswered | wasRinging=$wasRinging | callStart=$callStart")
                when {
                    callAnswered && callStart > 0 -> {
                        val duration = ((System.currentTimeMillis() - callStart) / 1000).toInt()
                        Log.e(TAG, "SAVING call: $savedNumber | ${duration}s")
                        stopService(context, savedNumber, duration, isIncoming)
                    }
                    else -> {
                        Log.e(TAG, "NOT SAVING — rejected/missed: $savedNumber")
                        if (callAnswered) cancelService(context)
                    }
                }
                callAnswered = false
                wasRinging   = false
                callStart    = 0
                savedNumber  = "Unknown"
            }
        }
    }

    private fun startService(context: Context, number: String, incoming: Boolean) {
        val i = Intent(context, CallMonitorService::class.java).apply {
            action = CallMonitorService.ACTION_START_RECORDING
            putExtra(CallMonitorService.EXTRA_PHONE_NUMBER, number)
            putExtra(CallMonitorService.EXTRA_IS_INCOMING, incoming)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
        else context.startService(i)
    }

    private fun stopService(context: Context, number: String, duration: Int, incoming: Boolean) {
        val i = Intent(context, CallMonitorService::class.java).apply {
            action = CallMonitorService.ACTION_STOP_RECORDING
            putExtra(CallMonitorService.EXTRA_PHONE_NUMBER, number)
            putExtra(CallMonitorService.EXTRA_DURATION, duration)
            putExtra(CallMonitorService.EXTRA_IS_INCOMING, incoming)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
        else context.startService(i)
    }

    private fun cancelService(context: Context) {
        val i = Intent(context, CallMonitorService::class.java).apply {
            action = CallMonitorService.ACTION_CANCEL_RECORDING
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
        else context.startService(i)
    }
}