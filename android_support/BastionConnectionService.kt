package app.bastion.bastion_meshtastic

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*

/** Explicit, non-sticky BLE session lease. Never restarts on boot/process death. */
class BastionConnectionService : Service() {
    companion object {
        const val STOP = "app.bastion.STOP_CONNECTION"
        const val CHANNEL = "bastion_connection_v1"
        const val NOTIFICATION = 2405
        var active = false
        var heartbeatAt = 0L
    }
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var status = "Screen-off monitoring enabled"
    private var startedAt = 0L
    private val watchdog = object : Runnable {
        override fun run() {
            val now = SystemClock.elapsedRealtime()
            if (now - heartbeatAt > 90_000L || now - startedAt >= 6 * 60 * 60 * 1000L) {
                status = "Connection lease ended"
                stopSelf()
            } else handler.postDelayed(this, 30_000L)
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) { stopSelf(); return START_NOT_STICKY }
        status = intent?.getStringExtra("status")?.take(100) ?: status
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL, "Bastion screen-off connection", NotificationManager.IMPORTANCE_LOW)
                )
            }
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else startForeground(NOTIFICATION, notification())
            if (!active) {
                startedAt = SystemClock.elapsedRealtime()
                heartbeatAt = startedAt
                wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Bastion:MeshConnection")
                    .apply { setReferenceCounted(false); acquire(6 * 60 * 60 * 1000L) }
                handler.postDelayed(watchdog, 30_000L)
            }
            active = true
            FieldBridge.started()
        } catch (e: Exception) {
            FieldBridge.startFailed(e.message ?: "Service could not start")
            stopSelf()
        }
        return START_NOT_STICKY
    }
    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, BastionConnectionService::class.java)
            .setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(R.drawable.ic_stat_bastion).setContentTitle("Bastion mesh connection")
            .setContentText(status).setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .addAction(Notification.Action.Builder(null, "STOP", stop).build()).build()
    }
    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() {
        active = false
        handler.removeCallbacks(watchdog)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        FieldBridge.stopped()
        super.onDestroy()
    }
}
