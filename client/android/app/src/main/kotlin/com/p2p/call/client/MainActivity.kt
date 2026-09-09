package com.p2p.call.client

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.p2p.call.client/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCallService" -> {
                    val peerId = call.argument<String>("peerId") ?: "对端用户"
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_START
                        putExtra(CallForegroundService.EXTRA_PEER_ID, peerId)
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        // Foreground service start may be restricted when the app
                        // is in the background (Android 12+). The call can still
                        // proceed without the keep-alive service.
                        result.success(false)
                    }
                }
                "stopCallService" -> {
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
