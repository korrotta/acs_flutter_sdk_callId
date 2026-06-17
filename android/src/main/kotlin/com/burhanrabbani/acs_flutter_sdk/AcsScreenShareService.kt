package com.burhanrabbani.acs_flutter_sdk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class AcsScreenShareService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val channelId = CHANNEL_ID
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(channelId) == null) {
                val channel = NotificationChannel(
                    channelId,
                    "Screen sharing",
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description = "Screen sharing status"
                manager.createNotificationChannel(channel)
            }
        }

        val appLabel = applicationInfo.loadLabel(packageManager)?.toString() ?: "Screen sharing"
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle(appLabel)
                .setContentText("Screen sharing is active")
                .setSmallIcon(notificationIcon())
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .build()
        } else {
            Notification.Builder(this)
                .setContentTitle(appLabel)
                .setContentText("Screen sharing is active")
                .setSmallIcon(notificationIcon())
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .build()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun notificationIcon(): Int {
        val icon = applicationInfo.icon
        return if (icon != 0) icon else android.R.drawable.ic_menu_camera
    }

    companion object {
        private const val CHANNEL_ID = "acs_screen_share"
        private const val NOTIFICATION_ID = 4007

        fun start(context: Context) {
            val intent = Intent(context, AcsScreenShareService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, AcsScreenShareService::class.java)
            context.stopService(intent)
        }
    }
}
