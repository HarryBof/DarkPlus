import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'dim_settings.dart';
import 'settings_store.dart';

/// Full-screen click-through tint layer rendered inside the overlay engine.
/// Intentionally renders no extra HUD controls on top of other apps.
class DarkLayerOverlay extends StatefulWidget {
  const DarkLayerOverlay({
    super.key,
    this.initialBrightnessLoader,
    this.brightnessStream,
    this.overlayMessageStream,
    this.settingsLoader,
  });

  final Future<double> Function()? initialBrightnessLoader;
  final Stream<double>? brightnessStream;
  final Stream<dynamic>? overlayMessageStream;
  final Future<DimSettings> Function()? settingsLoader;

  @override
  State<DarkLayerOverlay> createState() => _DarkLayerOverlayState();
}

class _DarkLayerOverlayState extends State<DarkLayerOverlay>
    with WidgetsBindingObserver {
  final SettingsStore _defaultStore = SettingsStore();

  DimSettings _settings = const DimSettings();
  double? _systemBrightness;
  StreamSubscription<double>? _brightnessSub;
  StreamSubscription<dynamic>? _messageSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncStateFromPlatform();
    _subscribeStreams();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // OverlayService triggers appIsResumed() whenever the overlay is shown,
    // including cold starts from the Quick Settings tile.
    if (state == AppLifecycleState.resumed) {
      _syncStateFromPlatform();
    }
  }

  Future<void> _syncStateFromPlatform() async {
    final settingsFuture = (widget.settingsLoader ?? _defaultStore.load)();
    final brightnessFuture =
        (widget.initialBrightnessLoader ?? () => ScreenBrightness().system)()
            .then<double?>((v) => v)
            .catchError((_) => null);

    final loadedSettings = await settingsFuture;
    final loadedBrightness = await brightnessFuture;

    if (!mounted) return;
    setState(() {
      _settings = loadedSettings;
      if (loadedBrightness != null) {
        _systemBrightness = loadedBrightness;
      }
    });
  }

  void _subscribeStreams() {
    final brightnessStream =
        widget.brightnessStream ??
        ScreenBrightness().onSystemScreenBrightnessChanged;
    _brightnessSub = brightnessStream.listen((brightness) {
      if (!mounted) return;
      setState(() {
        _systemBrightness = brightness;
      });
    }, onError: (_) {});

    final messageStream =
        widget.overlayMessageStream ?? FlutterOverlayWindow.overlayListener;
    _messageSub = messageStream.listen((message) {
      if (!mounted || message is! Map) return;
      setState(() {
        _settings = DimSettings.fromMap(message);
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _brightnessSub?.cancel();
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _settings.overlayColor(_systemBrightness);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          height: double.infinity,
          color: color,
        ),
      ),
    );
  }
}
