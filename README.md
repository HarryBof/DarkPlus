# DarkPlus

A lightweight Android screen dimmer overlay for comfortable night-time viewing when your phone's lowest system brightness is still too bright.

## Features

- **Auto & Manual Modes**: Automatically scales dimming intensity inversely with system brightness, or locks to a fixed manual dim level.
- **Warm Blue-Light Filter**: Adds an adjustable warm amber tint to reduce eye strain at night.
- **Safe Opacity Clamp**: Caps overlay opacity at 90% so you can never accidentally black out your screen.
- **Pure Click-Through Overlay**: Covers the full display (including status bar, navigation bar, and orientation changes) with zero extra floating HUD buttons on top of other apps.
- **Android Quick Settings Tile**: Toggle DarkPlus directly from your notification shade.
- **Persistent Settings**: Mode, dim strength, and warm tint settings are saved locally and automatically restored when toggled from Quick Settings.

## Permissions

- `SYSTEM_ALERT_WINDOW` (*Display over other apps*): Required to draw the click-through dimming overlay above other apps.
- `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_SPECIAL_USE`: Required on Android 14+ to keep the overlay service running reliably.
- `POST_NOTIFICATIONS` (optional on Android 13+): Displays the active foreground service notification.

## Building & Testing

```bash
# Run static analysis
flutter analyze

# Run unit and widget tests
flutter test

# Build release APK
flutter build apk --release
```

The compiled APK is output to `build/app/outputs/flutter-apk/app-release.apk`.

## Download

Pre-built APKs are published under [GitHub Releases](https://github.com/HarryBof/DarkPlus/releases).
