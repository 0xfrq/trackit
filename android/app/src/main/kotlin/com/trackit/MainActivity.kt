package com.trackit

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "trackit/android"
    private val queue = TrackitNotificationQueue(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessEnabled" -> result.success(TrackitNotificationListener.isEnabled(this))
                "openNotificationSettings" -> { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(null) }
                "drainCandidates" -> result.success(queue.read().map { it.toMap() })
                "acknowledgeCandidate" -> { queue.remove(call.arguments as String); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
