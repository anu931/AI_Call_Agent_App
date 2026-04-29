package io.flutter;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.telephony.TelephonyManager;

import androidx.core.content.ContextCompat;

public class CallReceiver extends BroadcastReceiver {

    private static String lastState = "";
    private static String currentNumber = "";

    @Override
    public void onReceive(Context context, Intent intent) {

        String state = intent.getStringExtra(TelephonyManager.EXTRA_STATE);
        String number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER);

        if (state == null) return;

        // Prevent duplicate triggers
        if (state.equals(lastState)) return;
        lastState = state;

        if (state.equals(TelephonyManager.EXTRA_STATE_RINGING)) {

            currentNumber = number;

        }
        else if (state.equals(TelephonyManager.EXTRA_STATE_OFFHOOK)) {

            Intent serviceIntent = new Intent(context, CallMonitorService.class);
            serviceIntent.putExtra("number", currentNumber);

            ContextCompat.startForegroundService(context, serviceIntent);

        }
        else if (state.equals(TelephonyManager.EXTRA_STATE_IDLE)) {

            Intent stopIntent = new Intent(context, CallMonitorService.class);
            context.stopService(stopIntent);

        }
    }
}