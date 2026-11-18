import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'dim_settings.dart';
import 'settings_store.dart';

/// Abstraction over overlay & system calls so [HomePage] can be unit/widget tested.
abstract class DarkPlusController {
  Future<bool> isPermissionGranted();
  Future<bool> requestPermission();
  Future<bool> isActive();
  Future<void> showOverlay({required int heightPx});
  Future<void> closeOverlay();
  Future<void> shareSettings(DimSettings settings);
  Future<void> refreshQuickTile();
  Future<void> requestNotificationPermission();
  Future<int?> getMaxOverlayHeightPx();
  Future<double?> getSystemBrightness();
  Stream<double> get onSystemBrightnessChanged;
  void setExternalStateListener(void Function(bool isActive)? onChanged);
}

class PlatformDarkPlusController implements DarkPlusController {
  static const MethodChannel _systemChannel = MethodChannel(
    'com.example.darkplus/system',
  );

  @override
  Future<bool> isPermissionGranted() =>
      FlutterOverlayWindow.isPermissionGranted();

  @override
  Future<bool> requestPermission() async =>
      await FlutterOverlayWindow.requestPermission() ?? false;

  @override
  Future<bool> isActive() => FlutterOverlayWindow.isActive();

  @override
  Future<void> showOverlay({required int heightPx}) async {
    await FlutterOverlayWindow.showOverlay(
      enableDrag: false,
      flag: OverlayFlag.clickThrough,
      alignment: OverlayAlignment.center,
      visibility: NotificationVisibility.visibilitySecret,
      overlayTitle: 'DarkPlus active',
      overlayContent: 'Tap Quick Settings tile or open app to adjust',
      width: WindowSize.matchParent,
      height: heightPx,
    );
  }

  @override
  Future<void> closeOverlay() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  @override
  Future<void> shareSettings(DimSettings settings) async {
    await FlutterOverlayWindow.shareData(settings.toMap());
  }

  @override
  Future<void> refreshQuickTile() async {
    try {
      await _systemChannel.invokeMethod<void>('refreshTile');
    } catch (_) {}
  }

  @override
  Future<void> requestNotificationPermission() async {
    try {
      await _systemChannel.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  @override
  Future<int?> getMaxOverlayHeightPx() async {
    try {
      return await _systemChannel.invokeMethod<int>('getMaxOverlayHeightPx');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<double?> getSystemBrightness() async {
    try {
      return await ScreenBrightness().system;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<double> get onSystemBrightnessChanged =>
      ScreenBrightness().onSystemScreenBrightnessChanged;

  @override
  void setExternalStateListener(void Function(bool isActive)? onChanged) {
    if (onChanged == null) {
      _systemChannel.setMethodCallHandler(null);
      return;
    }
    _systemChannel.setMethodCallHandler((call) async {
      if (call.method == 'onOverlayStateChanged' && call.arguments is bool) {
        onChanged(call.arguments as bool);
      }
    });
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller, this.settingsStore});

  final DarkPlusController? controller;
  final SettingsStore? settingsStore;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final DarkPlusController _controller;
  late final SettingsStore _store;

  bool _isActive = false;
  bool _hasPermission = true;
  bool _isBusy = false;
  bool _askedNotificationPermission = false;
  double? _systemBrightness;
  DimSettings _settings = const DimSettings();
  StreamSubscription<double>? _brightnessSub;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PlatformDarkPlusController();
    _store = widget.settingsStore ?? SettingsStore();
    WidgetsBinding.instance.addObserver(this);

    _controller.setExternalStateListener((isActive) {
      if (!mounted) return;
      setState(() => _isActive = isActive);
    });

    _brightnessSub = _controller.onSystemBrightnessChanged.listen((value) {
      if (!mounted) return;
      setState(() => _systemBrightness = value);
    }, onError: (_) {});

    _initialize();
  }

  Future<void> _initialize() async {
    final results = await Future.wait<dynamic>([
      _store.load(),
      _controller.getSystemBrightness(),
      _controller.isPermissionGranted(),
      _controller.isActive(),
    ]);
    if (!mounted) return;
    final loaded = results[0] as DimSettings;
    final brightness = results[1] as double?;
    final hasPermission = results[2] as bool;
    final active = results[3] as bool;

    setState(() {
      _settings = loaded;
      _systemBrightness = brightness;
      _hasPermission = hasPermission;
      _isActive = active;
    });
    if (active) {
      await _controller.shareSettings(loaded);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncOverlayStatus();
    }
  }

  Future<void> _syncOverlayStatus() async {
    final hasPermission = await _controller.isPermissionGranted();
    final active = await _controller.isActive();
    final brightness = await _controller.getSystemBrightness();
    if (!mounted) return;
    setState(() {
      _hasPermission = hasPermission;
      _isActive = active;
      if (brightness != null) {
        _systemBrightness = brightness;
      }
    });
    if (active) {
      await _controller.shareSettings(_settings);
    }
  }

  Future<void> _requestPermissionOnly() async {
    final granted = await _controller.requestPermission();
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    await _controller.refreshQuickTile();
  }

  Future<int> _resolveOverlayHeightPx() async {
    final nativeHeight = await _controller.getMaxOverlayHeightPx();
    if (nativeHeight != null && nativeHeight > 0) {
      return nativeHeight;
    }
    if (!mounted) return 3200;
    final physical = View.of(context).physicalSize;
    return math.max(physical.width, physical.height).ceil() + 400;
  }

  Future<void> _toggleFilter(bool enable) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      if (enable) {
        var granted = await _controller.isPermissionGranted();
        if (!granted) {
          granted = await _controller.requestPermission();
          if (!mounted) return;
          setState(() => _hasPermission = granted);
          if (!granted) {
            await _controller.refreshQuickTile();
            return;
          }
        }

        if (!_askedNotificationPermission) {
          _askedNotificationPermission = true;
          await _controller.requestNotificationPermission();
        }

        await _store.save(_settings);
        final heightPx = await _resolveOverlayHeightPx();
        await _controller.showOverlay(heightPx: heightPx);
        await _controller.shareSettings(_settings);
      } else {
        await _controller.closeOverlay();
      }

      final active = await _controller.isActive();
      if (!mounted) return;
      setState(() => _isActive = active);
      await _controller.refreshQuickTile();
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _updateSettings(DimSettings updated) async {
    setState(() => _settings = updated);
    await _store.save(updated);
    if (_isActive) {
      await _controller.shareSettings(updated);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.setExternalStateListener(null);
    _brightnessSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveOpacity = _settings.effectiveOpacity(_systemBrightness);
    final previewColor = _settings.overlayColor(_systemBrightness);
    final brightnessPercent = _systemBrightness == null
        ? '--'
        : '${(_systemBrightness! * 100).round()}%';
    final dimPercent = '${(effectiveOpacity * 100).round()}%';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            _buildHeader(theme),
            const SizedBox(height: 16),
            if (!_hasPermission) ...[
              _buildPermissionBanner(theme),
              const SizedBox(height: 16),
            ],
            _buildPowerCard(theme, dimPercent, brightnessPercent, previewColor),
            const SizedBox(height: 16),
            _buildControlsCard(theme),
            const SizedBox(height: 16),
            _buildTileTipCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _isActive
                ? Colors.amber.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.nightlight_round,
            color: _isActive ? Colors.amberAccent : Colors.white70,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DarkPlus',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Night screen dimmer',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _isActive
                ? Colors.greenAccent.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isActive
                  ? Colors.greenAccent.withValues(alpha: 0.45)
                  : Colors.white12,
            ),
          ),
          child: Text(
            _isActive ? 'ACTIVE' : 'OFF',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _isActive ? Colors.greenAccent : Colors.white60,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_outlined, color: Colors.orangeAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Display-over-apps permission is required to dim other screens.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _requestPermissionOnly,
            child: const Text('Grant'),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerCard(
    ThemeData theme,
    String dimPercent,
    String brightnessPercent,
    Color previewColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isActive ? 'Dimmer enabled' : 'Dimmer paused',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _settings.mode == DimMode.auto
                          ? 'Brightness: $brightnessPercent  •  Dim: $dimPercent'
                          : 'Manual dim level: $dimPercent',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 1.25,
                child: Switch(
                  key: const Key('power_switch'),
                  value: _isActive,
                  activeThumbColor: Colors.greenAccent,
                  activeTrackColor: Colors.greenAccent.withValues(alpha: 0.35),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  onChanged: _isBusy ? null : _toggleFilter,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 22,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE0E0E0), Color(0xFF90CAF9)],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Filter preview',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ColoredBox(color: previewColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard(ThemeData theme) {
    final isAuto = _settings.mode == DimMode.auto;
    final strengthValue = isAuto
        ? _settings.autoIntensity
        : _settings.manualOpacity;
    final strengthPercent = '${(strengthValue * 100).round()}%';
    final warmthPercent = '${(_settings.warmth * 100).round()}%';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mode',
            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<DimMode>(
              key: const Key('mode_selector'),
              segments: const [
                ButtonSegment(
                  value: DimMode.auto,
                  icon: Icon(Icons.brightness_auto, size: 18),
                  label: Text('Auto'),
                ),
                ButtonSegment(
                  value: DimMode.manual,
                  icon: Icon(Icons.tune, size: 18),
                  label: Text('Manual'),
                ),
              ],
              selected: {_settings.mode},
              onSelectionChanged: (selected) {
                _updateSettings(_settings.copyWith(mode: selected.first));
              },
            ),
          ),
          const SizedBox(height: 20),
          _buildSliderRow(
            theme: theme,
            label: isAuto ? 'Auto dim strength' : 'Manual dim level',
            valueLabel: strengthPercent,
          ),
          Slider(
            key: const Key('strength_slider'),
            value: strengthValue,
            min: isAuto
                ? DimSettings.minAutoIntensity
                : DimSettings.minManualOpacity,
            max: isAuto ? 1.0 : DimSettings.maxSafeOpacity,
            activeColor: Colors.greenAccent,
            onChanged: (value) {
              _updateSettings(
                isAuto
                    ? _settings.copyWith(autoIntensity: value)
                    : _settings.copyWith(manualOpacity: value),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSliderRow(
            theme: theme,
            label: 'Warm blue-light filter',
            valueLabel: warmthPercent,
          ),
          Slider(
            key: const Key('warmth_slider'),
            value: _settings.warmth,
            min: 0.0,
            max: 1.0,
            activeColor: Colors.amberAccent,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(warmth: value));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required ThemeData theme,
    required String label,
    required String valueLabel,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        Text(
          valueLabel,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildTileTipCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.grid_view_rounded, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tip: Add the DarkPlus tile to Android Quick Settings to toggle the dimmer from anywhere.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }
}
