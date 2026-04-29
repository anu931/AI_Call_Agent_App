package io.flutter;

import android.content.Context;
import android.media.MediaRecorder;
import android.os.Environment;

import java.io.File;
import java.io.IOException;

public class CallRecorder {

    private MediaRecorder recorder;
    private String filePath;

    public String startRecording(Context context) {
        try {
            File dir = new File(context.getExternalFilesDir(null), "call_recordings");
            if (!dir.exists()) {
                dir.mkdirs();
            }
            filePath = dir.getAbsolutePath() + "/call_" + System.currentTimeMillis() + ".mp3";
            recorder = new MediaRecorder();
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC);
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
            recorder.setOutputFile(filePath);
            recorder.prepare();
            recorder.start();

        } catch (IOException e) {
            e.printStackTrace();
        }

        return filePath;
    }

    public void stopRecording() {

        try {

            if (recorder != null) {

                recorder.stop();
                recorder.release();
                recorder = null;

            }

        } catch (Exception e) {
            e.printStackTrace();
        }

    }
}