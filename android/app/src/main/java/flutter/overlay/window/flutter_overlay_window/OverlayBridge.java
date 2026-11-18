package flutter.overlay.window.flutter_overlay_window;

import android.content.Context;
import android.content.Intent;
import android.content.res.Resources;
import android.graphics.Point;
import android.graphics.Rect;
import android.os.Build;
import android.view.Display;
import android.view.WindowManager;
import android.view.WindowMetrics;

/**
 * Bridge within the plugin package to configure WindowSetup defaults and toggle
 * OverlayService safely when launched from the Quick Settings tile without MainActivity.
 */
public final class OverlayBridge {
    private OverlayBridge() {}

    public static boolean isOverlayRunning() {
        return OverlayService.isRunning;
    }

    public static int computeMaxOverlayHeightPx(Context context) {
        WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        int maxSide = 3200;
        if (wm != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowMetrics metrics = wm.getMaximumWindowMetrics();
                Rect bounds = metrics.getBounds();
                maxSide = Math.max(bounds.width(), bounds.height());
            } else {
                @SuppressWarnings("deprecation")
                Display display = wm.getDefaultDisplay();
                Point size = new Point();
                display.getRealSize(size);
                maxSide = Math.max(size.x, size.y);
            }
        }
        Resources res = context.getResources();
        int statusId = res.getIdentifier("status_bar_height", "dimen", "android");
        int navId = res.getIdentifier("navigation_bar_height", "dimen", "android");
        int statusPx = statusId > 0 ? res.getDimensionPixelSize(statusId) : 100;
        int navPx = navId > 0 ? res.getDimensionPixelSize(navId) : 150;
        return maxSide + statusPx + navPx + 200;
    }

    public static void prepareFullScreenClickThrough(Context context) {
        WindowSetup.width = WindowManager.LayoutParams.MATCH_PARENT;
        WindowSetup.height = computeMaxOverlayHeightPx(context);
        WindowSetup.enableDrag = false;
        WindowSetup.positionGravity = "none";
        WindowSetup.setFlag("clickThrough");
        WindowSetup.setGravityFromAlignment("center");
        WindowSetup.setNotificationVisibility("visibilitySecret");
        WindowSetup.overlayTitle = "DarkPlus active";
        WindowSetup.overlayContent = "Tap Quick Settings tile or open app to adjust";
    }

    public static boolean toggleOverlayFromTile(Context context) {
        Intent intent = new Intent(context, OverlayService.class);
        if (OverlayService.isRunning) {
            context.stopService(intent);
            return false;
        }
        prepareFullScreenClickThrough(context);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        return true;
    }
}
