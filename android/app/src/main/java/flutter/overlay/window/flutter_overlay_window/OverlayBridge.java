package flutter.overlay.window.flutter_overlay_window;

import android.content.Context;
import android.content.Intent;
import android.content.res.Resources;
import android.graphics.Point;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.Display;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.view.WindowMetrics;

import java.lang.reflect.Field;

/**
 * Bridge within the plugin package to configure WindowSetup defaults, remove
 * FlutterView system-window inset padding (which otherwise clips the bottom
 * navigation bar), and toggle OverlayService safely from Quick Settings.
 */
public final class OverlayBridge {
    private static final Handler MAIN_HANDLER = new Handler(Looper.getMainLooper());

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
        int statusPx = statusId > 0 ? res.getDimensionPixelSize(statusId) : 120;
        int navPx = navId > 0 ? res.getDimensionPixelSize(navId) : 160;
        // Generous margin on all sides so centered window covers both portrait
        // and landscape including system bars and camera cutouts.
        return maxSide + statusPx + navPx + 1000;
    }

    public static void prepareFullScreenClickThrough(Context context) {
        int size = computeMaxOverlayHeightPx(context);
        WindowSetup.width = size;
        WindowSetup.height = size;
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
        intent.putExtra("startX", 0);
        intent.putExtra("startY", 0);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        scheduleFullScreenFix(context.getApplicationContext());
        return true;
    }

    /**
     * Schedules layout & inset fixes on the active OverlayService FlutterView
     * so setFitsSystemWindows(true) in OverlayService does not pad out the
     * bottom navigation bar or status bar.
     */
    public static void scheduleFullScreenFix(Context context) {
        final Context appContext = context.getApplicationContext();
        int[] delaysMs = {0, 30, 100, 250, 500};
        for (int delay : delaysMs) {
            MAIN_HANDLER.postDelayed(() -> applyFullScreenFix(appContext), delay);
        }
    }

    private static void applyFullScreenFix(Context context) {
        try {
            if (!OverlayService.isRunning) return;

            Field instanceField = OverlayService.class.getDeclaredField("instance");
            instanceField.setAccessible(true);
            Object serviceInstance = instanceField.get(null);
            if (serviceInstance == null) return;

            Field flutterViewField = OverlayService.class.getDeclaredField("flutterView");
            flutterViewField.setAccessible(true);
            View flutterView = (View) flutterViewField.get(serviceInstance);

            Field wmField = OverlayService.class.getDeclaredField("windowManager");
            wmField.setAccessible(true);
            WindowManager wm = (WindowManager) wmField.get(serviceInstance);

            if (flutterView == null || wm == null) return;

            // Undo OverlayService's flutterView.setFitsSystemWindows(true) which
            // otherwise adds bottom padding equal to the navigation bar inset.
            flutterView.setFitsSystemWindows(false);
            if (flutterView instanceof ViewGroup) {
                ViewGroup group = (ViewGroup) flutterView;
                group.setClipToPadding(false);
                group.setClipChildren(false);
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                flutterView.setOnApplyWindowInsetsListener((v, insets) -> {
                    v.setPadding(0, 0, 0, 0);
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        return WindowInsets.CONSUMED;
                    }
                    @SuppressWarnings("deprecation")
                    WindowInsets consumed = insets.consumeSystemWindowInsets();
                    return consumed;
                });
            }
            flutterView.setPadding(0, 0, 0, 0);

            ViewGroup.LayoutParams rawParams = flutterView.getLayoutParams();
            if (rawParams instanceof WindowManager.LayoutParams) {
                WindowManager.LayoutParams params = (WindowManager.LayoutParams) rawParams;
                int size = computeMaxOverlayHeightPx(context);
                params.width = size;
                params.height = size;
                params.x = 0;
                params.y = 0;
                params.gravity = Gravity.CENTER;
                params.flags &= ~WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR;
                params.flags |= WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    params.layoutInDisplayCutoutMode =
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    params.layoutInDisplayCutoutMode =
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
                }
                wm.updateViewLayout(flutterView, params);
            }
        } catch (Throwable ignored) {
        }
    }
}
