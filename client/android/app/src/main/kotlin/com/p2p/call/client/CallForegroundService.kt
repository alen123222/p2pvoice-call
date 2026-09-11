package com.p2p.call.client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class CallForegroundService : Service() {

    companion object {
        const val KEEPALIVE_CHANNEL_ID = "p2p_keepalive_channel"
        const val CALL_CHANNEL_ID = "p2p_call_channel"
        const val INCOMING_CHANNEL_ID = "p2p_incoming_call_channel"

        const val NOTIFICATION_ID = 9527
        const val NOTIFICATION_INCOMING_ID = 9528

        const val ACTION_START_KEEPALIVE = "com.p2p.call.client.ACTION_START_KEEPALIVE"
        const val ACTION_START_CALL = "com.p2p.call.client.ACTION_START"
        const val ACTION_STOP_CALL = "com.p2p.call.client.ACTION_STOP"
        const val ACTION_STOP_ALL = "com.p2p.call.client.ACTION_STOP_ALL"
        const val ACTION_SHOW_INCOMING = "com.p2p.call.client.ACTION_SHOW_INCOMING"
        const val ACTION_CANCEL_INCOMING = "com.p2p.call.client.ACTION_CANCEL_INCOMING"

        const val ACTION_ANSWER = "com.p2p.call.client.ACTION_ANSWER"
        const val ACTION_REJECT = "com.p2p.call.client.ACTION_REJECT"

        const val EXTRA_PEER_ID = "extra_peer_id"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var isKeepAliveActive: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_STICKY

        when (intent.action) {
            ACTION_START_KEEPALIVE -> {
                isKeepAliveActive = true
                startKeepAliveForeground()
                acquireWakeLock()
            }
            ACTION_START_CALL -> {
                val peerId = intent.getStringExtra(EXTRA_PEER_ID) ?: "对端用户"
                cancelIncomingNotification()
                startCallForeground(peerId)
                acquireWakeLock()
            }
            ACTION_STOP_CALL -> {
                cancelIncomingNotification()
                if (isKeepAliveActive) {
                    startKeepAliveForeground()
                } else {
                    releaseWakeLock()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
            ACTION_SHOW_INCOMING -> {
                val callerId = intent.getStringExtra(EXTRA_PEER_ID) ?: "未知来电用户"
                showIncomingCallNotification(callerId)
                acquireWakeLock()
            }
            ACTION_CANCEL_INCOMING -> {
                cancelIncomingNotification()
            }
            ACTION_STOP_ALL -> {
                isKeepAliveActive = false
                cancelIncomingNotification()
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }

        return START_STICKY
    }

    private fun startKeepAliveForeground() {
        val notificationIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification: Notification = NotificationCompat.Builder(this, KEEPALIVE_CHANNEL_ID)
            .setContentTitle("🟢 P2P 语音通话在线中")
            .setContentText("已在后台保持连接，随时可接收来电呼叫")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            } catch (e: Exception) {
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startCallForeground(peerId: String) {
        val notificationIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification: Notification = NotificationCompat.Builder(this, CALL_CHANNEL_ID)
            .setContentTitle("📞 P2P 加密通话进行中")
            .setContentText("通话对象: $peerId (点击返回通话)")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun showIncomingCallNotification(callerId: String) {
        // The content & full-screen intents must only OPEN the app so the
        // incoming-call UI is shown. Answering must never happen implicitly,
        // otherwise devices that honor full-screen intents will auto-answer.
        val openIncomingIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_PEER_ID, callerId)
        }

        val openIncomingPendingIntent = PendingIntent.getActivity(
            this,
            1,
            openIncomingIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val answerIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_ANSWER
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_PEER_ID, callerId)
        }
        val answerPendingIntent = PendingIntent.getActivity(
            this,
            2,
            answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val rejectIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_REJECT
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_PEER_ID, callerId)
        }
        val rejectPendingIntent = PendingIntent.getActivity(
            this,
            3,
            rejectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val notification: Notification = NotificationCompat.Builder(this, INCOMING_CHANNEL_ID)
            .setContentTitle("📞 收到实时语音通话呼叫")
            .setContentText("「$callerId」正在呼叫您...")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setOngoing(true)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 1000, 1000, 1000, 1000, 1000))
            .setContentIntent(openIncomingPendingIntent)
            .setFullScreenIntent(openIncomingPendingIntent, true)
            .addAction(android.R.drawable.ic_menu_call, "接听", answerPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "挂断", rejectPendingIntent)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_INCOMING_ID, notification)
    }

    private fun cancelIncomingNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_INCOMING_ID)
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "P2PVoiceCall::CallWakeLock"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return

            // 1. KeepAlive Channel (静默保活)
            val keepAliveChannel = NotificationChannel(
                KEEPALIVE_CHANNEL_ID,
                "P2P 后台在线保活",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持应用在后台连接信令服务器，确保不错过任何呼叫"
                setShowBadge(false)
            }
            manager.createNotificationChannel(keepAliveChannel)

            // 2. Active Call Channel (通话中)
            val callChannel = NotificationChannel(
                CALL_CHANNEL_ID,
                "P2P 通话进行中",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持通话与录音麦克风后台运行"
                setShowBadge(false)
            }
            manager.createNotificationChannel(callChannel)

            // 3. Incoming Call Channel (高优先级弹出式强提醒)
            val incomingSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .build()

            val incomingChannel = NotificationChannel(
                INCOMING_CHANNEL_ID,
                "P2P 来电通知",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "收到外部呼叫时的浮动横幅弹出通知与铃声震动"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 1000, 1000, 1000, 1000)
                setSound(incomingSoundUri, audioAttributes)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(incomingChannel)
        }
    }

    override fun onDestroy() {
        cancelIncomingNotification()
        releaseWakeLock()
        super.onDestroy()
    }
}
