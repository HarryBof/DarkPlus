import 'dart:async';

import 'package:darkplus/dim_settings.dart';
import 'package:darkplus/home_page.dart';
import 'package:darkplus/overlay_layer.dart';
import 'package:darkplus/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemorySettingsStore extends SettingsStore {
  DimSettings current = const DimSettings();

  @override
  Future<DimSettings> load() async => current;

  @override
  Future<void> save(DimSettings settings) async {
    current = settings;
  }
}

class FakeDarkPlusController implements DarkPlusController {
  bool permissionGranted = true;
  bool active = false;
  double? systemBrightness = 0.2;
  int? maxHeightPx = 2800;
  int? lastShownHeightPx;
  int showCalls = 0;
  int closeCalls = 0;
  int refreshTileCalls = 0;
  DimSettings? lastSharedSettings;
  void Function(bool)? externalListener;

  final StreamController<double> brightnessController =
      StreamController<double>.broadcast();

  @override
  Future<bool> isPermissionGranted() async => permissionGranted;

  @override
  Future<bool> requestPermission() async {
    permissionGranted = true;
    return true;
  }

  @override
  Future<bool> isActive() async => active;

  @override
  Future<void> showOverlay({required int heightPx}) async {
    showCalls++;
    lastShownHeightPx = heightPx;
    active = true;
  }

  @override
  Future<void> closeOverlay() async {
    closeCalls++;
    active = false;
  }

  @override
  Future<void> shareSettings(DimSettings settings) async {
    lastSharedSettings = settings;
  }

  @override
  Future<void> refreshQuickTile() async {
    refreshTileCalls++;
  }

  @override
  Future<void> requestNotificationPermission() async {}

  @override
  Future<int?> getMaxOverlayHeightPx() async => maxHeightPx;

  @override
  Future<double?> getSystemBrightness() async => systemBrightness;

  @override
  Stream<double> get onSystemBrightnessChanged => brightnessController.stream;

  @override
  void setExternalStateListener(void Function(bool isActive)? onChanged) {
    externalListener = onChanged;
  }

  void dispose() {
    brightnessController.close();
  }
}

void main() {
  group('DarkLayerOverlay', () {
    testWidgets('fetches initial brightness immediately on mount', (
      tester,
    ) async {
      final brightnessStream = StreamController<double>.broadcast();
      final messageStream = StreamController<dynamic>.broadcast();
      addTearDown(() async {
        await brightnessStream.close();
        await messageStream.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DarkLayerOverlay(
            initialBrightnessLoader: () async => 0.2,
            brightnessStream: brightnessStream.stream,
            overlayMessageStream: messageStream.stream,
            settingsLoader: () async =>
                const DimSettings(mode: DimMode.auto, autoIntensity: 1.0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color!.a, closeTo(0.8, 0.02));
      // No HUD text or buttons rendered on top of other apps.
      expect(find.byType(Text), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('updates opacity on brightness stream and live message', (
      tester,
    ) async {
      final brightnessStream = StreamController<double>.broadcast();
      final messageStream = StreamController<dynamic>.broadcast();
      addTearDown(() async {
        await brightnessStream.close();
        await messageStream.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DarkLayerOverlay(
            initialBrightnessLoader: () async => 0.8,
            brightnessStream: brightnessStream.stream,
            overlayMessageStream: messageStream.stream,
            settingsLoader: () async =>
                const DimSettings(mode: DimMode.auto, autoIntensity: 1.0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      brightnessStream.add(0.3);
      await tester.pumpAndSettle();

      var container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      var color = (container.decoration as BoxDecoration).color!;
      expect(color.a, closeTo(0.7, 0.02));

      messageStream.add(
        const DimSettings(
          mode: DimMode.manual,
          manualOpacity: 0.45,
          warmth: 1.0,
        ).toMap(),
      );
      await tester.pumpAndSettle();

      container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      color = (container.decoration as BoxDecoration).color!;
      expect(color.a, closeTo(0.45, 0.02));
      expect(color.r, greaterThan(0.1));
    });
  });

  group('HomePage', () {
    late InMemorySettingsStore store;
    late FakeDarkPlusController controller;

    setUp(() {
      store = InMemorySettingsStore();
      controller = FakeDarkPlusController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('shows permission banner when missing and activates on toggle', (
      tester,
    ) async {
      controller.permissionGranted = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: HomePage(controller: controller, settingsStore: store),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Grant'), findsOneWidget);
      expect(find.text('OFF'), findsOneWidget);

      await tester.tap(find.byKey(const Key('power_switch')));
      await tester.pumpAndSettle();

      expect(controller.showCalls, 1);
      expect(controller.lastShownHeightPx, 2800);
      expect(controller.refreshTileCalls, 1);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('Grant'), findsNothing);
    });

    testWidgets('switches modes, adjusts sliders, and shares live updates', (
      tester,
    ) async {
      controller.active = true;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: HomePage(controller: controller, settingsStore: store),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();

      expect(controller.lastSharedSettings?.mode, DimMode.manual);
      expect(find.text('Manual dim level'), findsOneWidget);

      // Simulate Quick Settings tile turning overlay off externally.
      controller.externalListener?.call(false);
      await tester.pumpAndSettle();

      expect(find.text('OFF'), findsOneWidget);
    });
  });
}
