import 'dart:io';

import 'package:darkplus/dim_settings.dart';
import 'package:darkplus/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DimSettings', () {
    test('auto mode scales with inverted brightness and clamps safely', () {
      const settings = DimSettings(mode: DimMode.auto, autoIntensity: 1.0);

      expect(settings.effectiveOpacity(1.0), 0.0);
      expect(settings.effectiveOpacity(0.5), 0.5);
      // Brightness 0.0 must clamp at maxSafeOpacity (0.90), never 1.0.
      expect(settings.effectiveOpacity(0.0), DimSettings.maxSafeOpacity);
    });

    test('auto mode scales by autoIntensity', () {
      const settings = DimSettings(mode: DimMode.auto, autoIntensity: 0.6);

      expect(settings.effectiveOpacity(0.0), closeTo(0.6, 1e-9));
      expect(settings.effectiveOpacity(0.5), closeTo(0.3, 1e-9));
      expect(settings.effectiveOpacity(null), closeTo(0.3, 1e-9));
    });

    test('manual mode ignores system brightness and clamps to safe bounds', () {
      const settings = DimSettings(mode: DimMode.manual, manualOpacity: 0.65);

      expect(settings.effectiveOpacity(1.0), 0.65);
      expect(settings.effectiveOpacity(0.0), 0.65);
    });

    test('overlayColor applies warmth tint while preserving opacity', () {
      const cool = DimSettings(
        mode: DimMode.manual,
        manualOpacity: 0.5,
        warmth: 0.0,
      );
      const warm = DimSettings(
        mode: DimMode.manual,
        manualOpacity: 0.5,
        warmth: 1.0,
      );

      final coolColor = cool.overlayColor(0.5);
      final warmColor = warm.overlayColor(0.5);

      expect(coolColor.a, closeTo(0.5, 0.01));
      expect(coolColor.r, 0.0);
      expect(warmColor.a, closeTo(0.5, 0.01));
      expect(warmColor.r, greaterThan(coolColor.r));
      expect(warmColor.r, greaterThan(warmColor.b));
    });

    test('toMap and fromMap roundtrip and clamp invalid values', () {
      const original = DimSettings(
        mode: DimMode.manual,
        autoIntensity: 0.75,
        manualOpacity: 0.42,
        warmth: 0.35,
      );
      expect(DimSettings.fromMap(original.toMap()), original);

      final clamped = DimSettings.fromMap({
        'mode': 'unknown',
        'autoIntensity': 5.0,
        'manualOpacity': 1.0,
        'warmth': -2.0,
      });
      expect(clamped.mode, DimMode.auto);
      expect(clamped.autoIntensity, 1.0);
      expect(clamped.manualOpacity, DimSettings.maxSafeOpacity);
      expect(clamped.warmth, 0.0);
    });
  });

  group('SettingsStore', () {
    late Directory tempDir;
    late SettingsStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('darkplus_test_');
      store = SettingsStore(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns defaults when file does not exist', () async {
      expect(await store.load(), const DimSettings());
    });

    test('saves and loads settings', () async {
      const settings = DimSettings(
        mode: DimMode.manual,
        autoIntensity: 0.65,
        manualOpacity: 0.40,
        warmth: 0.55,
      );
      await store.save(settings);
      expect(await store.load(), settings);
    });

    test('returns defaults when file contains corrupt JSON', () async {
      final file = File('${tempDir.path}/darkplus_settings.json');
      await file.writeAsString('{not valid json');
      expect(await store.load(), const DimSettings());
    });
  });
}
