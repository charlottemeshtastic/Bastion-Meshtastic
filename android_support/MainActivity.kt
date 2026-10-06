package app.bastion.bastion_meshtastic

import android.Manifest
import android.app.NotificationManager
import android.content.*
import android.content.pm.PackageManager
import android.os.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    var isForeground = false
    override fun onCreate(savedInstanceState: Bundle?) {
        FieldBridge.activity = WeakReference(this)
        if (FlutterEngineCache.getInstance().get(FieldBridge.ENGINE) == null) {
            val engine = FlutterEngine(applicationContext)
            FieldBridge.bind(engine, applicationContext)
            FlutterEngineCache.getInstance().put(FieldBridge.ENGINE, engine)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
        super.onCreate(savedInstanceState)
    }
    override fun getCachedEngineId(): String = FieldBridge.ENGINE
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun onResume() { super.onResume(); isForeground = true; FieldBridge.activity = WeakReference(this) }
    override fun onPause() { isForeground = false; FieldFiles.cancelFixOnBackground(); super.onPause() }
    override fun onDestroy() {
        if (FieldBridge.activity?.get() === this) FieldBridge.activity = null
        if (isFinishing && !isChangingConfigurations) {
            stopService(Intent(this, BastionConnectionService::class.java))
            FieldBridge.stopped()
        }
        super.onDestroy()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        FieldBridge.permissionsResult(requestCode, grantResults)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        FieldBridge.documentResult(requestCode, resultCode, data)
    }
}

object FieldBridge {
    const val ENGINE = "bastion_live_engine"
    var activity: WeakReference<MainActivity>? = null
    private lateinit var context: Context
    private lateinit var connection: MethodChannel
    private lateinit var field: MethodChannel
    private var startResult: MethodChannel.Result? = null
    private var notificationResult: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())
    fun bind(engine: FlutterEngine, ctx: Context) {
        context = ctx
        connection = MethodChannel(engine.dartExecutor.binaryMessenger, "bastion/connection")
        field = MethodChannel(engine.dartExecutor.binaryMessenger, "bastion/field")
        FieldFiles.bind(context, field)
        connection.setMethodCallHandler { call, result ->
            when (call.method) {
                "running" -> result.success(BastionConnectionService.active)
                "requestNotifications" -> {
                    val host = activity?.get()
                    if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (host?.isForeground != true || notificationResult != null) result.error("permission", "Open the app to allow notifications", null)
                        else { notificationResult = result; host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2401) }
                    } else result.success(context.getSystemService(NotificationManager::class.java).areNotificationsEnabled())
                }
                "start" -> {
                    val manager = context.getSystemService(NotificationManager::class.java)
                    val channelBlocked = Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(BastionConnectionService.CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE
                    if (activity?.get()?.isForeground != true) result.error("foreground", "Start screen-off mode while the app is visible", null)
                    else if (!manager.areNotificationsEnabled() || channelBlocked) result.error("notifications", "Allow the connection notification before starting", null)
                    else if (Build.VERSION.SDK_INT >= 31 && context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) result.error("bluetooth", "Bluetooth permission is required", null)
                    else if (startResult != null) result.error("busy", "Service is starting", null)
                    else {
                        try {
                            startResult = result
                            val intent = Intent(context, BastionConnectionService::class.java)
                                .putExtra("status", call.argument<String>("status")?.take(100))
                            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
                            handler.postDelayed({ if (startResult === result) startFailed("Service start timed out") }, 5_000L)
                        } catch (e: Exception) { startFailed(e.message ?: "Service start failed") }
                    }
                }
                "stop" -> { context.stopService(Intent(context, BastionConnectionService::class.java)); result.success(null) }
                "heartbeat" -> { BastionConnectionService.heartbeatAt = SystemClock.elapsedRealtime(); result.success(BastionConnectionService.active) }
                else -> result.notImplemented()
            }
        }
    }
    fun started() { startResult?.success(true); startResult = null }
    fun startFailed(message: String) { startResult?.error("service", message, null); startResult = null; context.stopService(Intent(context, BastionConnectionService::class.java)) }
    fun stopped() { if (::connection.isInitialized) connection.invokeMethod("stopped", null) }
    fun permissionsResult(code: Int, grants: IntArray) {
        if (code == 2401) { notificationResult?.success(grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED); notificationResult = null }
        else FieldFiles.permissionsResult(code, grants)
    }
    fun documentResult(code: Int, result: Int, data: Intent?) { FieldFiles.documentResult(code, result, data) }
}
