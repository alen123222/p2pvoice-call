package com.p2p.call.client

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.p2p.call.client/foreground_service"
    private var methodChannel: MethodChannel? = null
    private var pendingCallAction: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureLockScreenDisplay()
    }

    private fun configureLockScreenDisplay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialCallAction" -> {
                    result.success(pendingCallAction)
                    pendingCallAction = null
                }
                "startKeepAliveService" -> {
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_START_KEEPALIVE
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "startCallService" -> {
                    val peerId = call.argument<String>("peerId") ?: "对端用户"
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_START_CALL
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
                        result.success(false)
                    }
                }
                "stopCallService" -> {
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_STOP_CALL
                    }
                    try {
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "showIncomingCall" -> {
                    val peerId = call.argument<String>("peerId") ?: "未知来电用户"
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_SHOW_INCOMING
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
                        result.success(false)
                    }
                }
                "cancelIncomingCall" -> {
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_CANCEL_INCOMING
                    }
                    try {
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stopAllServices" -> {
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_STOP_ALL
                    }
                    try {
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        intent?.let { handleCallIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        configureLockScreenDisplay()
        handleCallIntent(intent)
    }

    private fun handleCallIntent(intent: Intent) {
        val action = intent.action ?: return
        val peerId = intent.getStringExtra(CallForegroundService.EXTRA_PEER_ID) ?: ""

        val callAction = when (action) {
            CallForegroundService.ACTION_ANSWER -> "answer"
            CallForegroundService.ACTION_REJECT -> "reject"
            else -> null
        }

        if (callAction != null) {
            val map = mapOf("action" to callAction, "peerId" to peerId)
            if (methodChannel != null) {
                methodChannel?.invokeMethod("onCallAction", map)
            } else {
                pendingCallAction = map
            }
        }
    }
}
