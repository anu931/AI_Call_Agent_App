package io.flutter;

import android.content.Intent;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {

    private static final String CHANNEL = "call_agent_channel";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                CHANNEL
        ).setMethodCallHandler((call, result) -> {

            if (call.method.equals("startService")) {

                Intent intent = new Intent(this, CallMonitorService.class);
                startForegroundService(intent);

                result.success("Service Started");

            } else {
                result.notImplemented();
            }
        });
    }
}