package io.flutter;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;

import androidx.core.app.NotificationCompat;

public class CallMonitorService extends Service {

    private static final String CHANNEL_ID = "call_channel";

    private CallRecorder recorder;
    private String audioPath;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Call Agent Running")
                .setContentText("Monitoring phone calls")
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .build();

        startForeground(1, notification);

        recorder = new CallRecorder();
        audioPath = recorder.startRecording(this);

        return START_STICKY;
    }

    @Override
    public void onDestroy() {

        if (recorder != null) {
            recorder.stopRecording();
        }

        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel() {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            NotificationChannel serviceChannel = new NotificationChannel(
                    CHANNEL_ID,
                    "Call Monitor Service",
                    NotificationManager.IMPORTANCE_LOW
            );

            NotificationManager manager = getSystemService(NotificationManager.class);

            if (manager != null) {
                manager.createNotificationChannel(serviceChannel);
            }
        }
    }
}