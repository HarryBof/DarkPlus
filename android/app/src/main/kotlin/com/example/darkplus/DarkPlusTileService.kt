package com.example.darkplus

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import flutter.overlay.window.flutter_overlay_window.OverlayBridge

@RequiresApi(Build.VERSION_CODES.N)
class DarkPlusTileService : TileService() {

    companion object {
        const val ACTION_OVERLAY_STATE_CHANGED = "com.example.darkplus.OVERLAY_STATE_CHANGED"
        const val EXTRA_IS_ACTIVE = "is_active"
    }

    override fun onStartListening() {
        super.onStartListening()
        syncTileState(OverlayBridge.isOverlayRunning())
    }

    override fun onClick() {
        super.onClick()
        if (!Settings.canDrawOverlays(this)) {
            openAppForPermission()
            return
        }

        val isActive = OverlayBridge.toggleOverlayFromTile(applicationContext)
        syncTileState(isActive)

        val broadcast = Intent(ACTION_OVERLAY_STATE_CHANGED).apply {
            setPackage(packageName)
            putExtra(EXTRA_IS_ACTIVE, isActive)
        }
        sendBroadcast(broadcast)
    }

    private fun openAppForPermission() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun syncTileState(isActive: Boolean) {
        val tile = qsTile ?: return
        val hasPermission = Settings.canDrawOverlays(this)
        tile.state = if (isActive && hasPermission) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when {
                !hasPermission -> "Needs permission"
                isActive -> "On"
                else -> "Off"
            }
        }
        tile.updateTile()
    }
}
