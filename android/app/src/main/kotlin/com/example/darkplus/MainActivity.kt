package com.example.darkplus

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.service.quicksettings.TileService
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import flutter.overlay.window.flutter_overlay_window.OverlayBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SYSTEM_CHANNEL = "com.example.darkplus/system"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 2001
    }

    private var systemChannel: MethodChannel? = null

    private val overlayStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != DarkPlusTileService.ACTION_OVERLAY_STATE_CHANGED) return
            val isActive = intent.getBooleanExtra(
                DarkPlusTileService.EXTRA_IS_ACTIVE,
                OverlayBridge.isOverlayRunning()
            )
            systemChannel?.invokeMethod("onOverlayStateChanged", isActive)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(DarkPlusTileService.ACTION_OVERLAY_STATE_CHANGED)
        ContextCompat.registerReceiver(
            this,
            overlayStateReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(overlayStateReceiver)
        } catch (_: IllegalArgumentException) {
        }
        systemChannel?.setMethodCallHandler(null)
        systemChannel = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        systemChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "refreshTile" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            TileService.requestListeningState(
                                this@MainActivity,
                                ComponentName(this@MainActivity, DarkPlusTileService::class.java)
                            )
                        }
                        result.success(null)
                    }
                    "getMaxOverlayHeightPx" -> {
                        result.success(OverlayBridge.computeMaxOverlayHeightPx(this@MainActivity))
                    }
                    "requestNotificationPermission" -> {
                        requestNotificationPermissionIfNeeded()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE
            )
        }
    }
}
