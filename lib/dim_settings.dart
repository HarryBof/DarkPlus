import 'package:flutter/material.dart';

/// How the overlay dimming level is determined.
enum DimMode {
  /// Automatically dims more as system brightness drops.
  auto,

  /// Uses a fixed user-selected dimming opacity.
  manual,
}

/// Immutable configuration for the DarkPlus screen overlay.
class DimSettings {
  /// Maximum allowed opacity so the user never locks themselves out with a
  /// pitch-black screen on older Android versions.
  static const double maxSafeOpacity = 0.90;
  static const double minManualOpacity = 0.05;
  static const double minAutoIntensity = 0.10;
  static const Color _warmTintTarget = Color(0xFF4A1900);

  const DimSettings({
    this.mode = DimMode.auto,
    this.autoIntensity = 0.85,
    this.manualOpacity = 0.50,
    this.warmth = 0.0,
  });

  final DimMode mode;
  final double autoIntensity;
  final double manualOpacity;
  final double warmth;

  DimSettings copyWith({
    DimMode? mode,
    double? autoIntensity,
    double? manualOpacity,
    double? warmth,
  }) {
    return DimSettings(
      mode: mode ?? this.mode,
      autoIntensity: (autoIntensity ?? this.autoIntensity).clamp(
        minAutoIntensity,
        1.0,
      ),
      manualOpacity: (manualOpacity ?? this.manualOpacity).clamp(
        minManualOpacity,
        maxSafeOpacity,
      ),
      warmth: (warmth ?? this.warmth).clamp(0.0, 1.0),
    );
  }

  /// Calculates the safe overlay opacity in `[0.0, maxSafeOpacity]`.
  double effectiveOpacity(double? systemBrightness) {
    if (mode == DimMode.manual) {
      return manualOpacity.clamp(minManualOpacity, maxSafeOpacity);
    }
    final brightness = (systemBrightness ?? 0.5).clamp(0.0, 1.0);
    final raw = (1.0 - brightness) * autoIntensity.clamp(minAutoIntensity, 1.0);
    return raw.clamp(0.0, maxSafeOpacity);
  }

  /// Computes the final ARGB overlay color from opacity and warmth.
  Color overlayColor(double? systemBrightness) {
    final base = Color.lerp(
      Colors.black,
      _warmTintTarget,
      warmth.clamp(0.0, 1.0),
    )!;
    return base.withValues(alpha: effectiveOpacity(systemBrightness));
  }

  Map<String, dynamic> toMap() => {
    'mode': mode.name,
    'autoIntensity': autoIntensity,
    'manualOpacity': manualOpacity,
    'warmth': warmth,
  };

  factory DimSettings.fromMap(Map<dynamic, dynamic> map) {
    final modeName = map['mode'] as String?;
    final mode = modeName == DimMode.manual.name
        ? DimMode.manual
        : DimMode.auto;
    return DimSettings(
      mode: mode,
      autoIntensity: ((map['autoIntensity'] as num?)?.toDouble() ?? 0.85).clamp(
        minAutoIntensity,
        1.0,
      ),
      manualOpacity: ((map['manualOpacity'] as num?)?.toDouble() ?? 0.50).clamp(
        minManualOpacity,
        maxSafeOpacity,
      ),
      warmth: ((map['warmth'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DimSettings &&
            other.mode == mode &&
            other.autoIntensity == autoIntensity &&
            other.manualOpacity == manualOpacity &&
            other.warmth == warmth;
  }

  @override
  int get hashCode => Object.hash(mode, autoIntensity, manualOpacity, warmth);
}
