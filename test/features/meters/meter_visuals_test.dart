import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app_theme.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_visuals.dart';

void main() {
  test('dark category text remains readable on cards and tinted badges', () {
    final scheme = AppTheme.dark().colorScheme;
    for (final type in MeterType.values) {
      final accent = meterColor(type, Brightness.dark);
      for (final surface in [scheme.surface, scheme.surfaceContainerLow]) {
        for (final alpha in [0.0, .10, .12, .14]) {
          final background = Color.alphaBlend(
            accent.withValues(alpha: alpha),
            surface,
          );
          expect(
            _contrast(accent, background),
            greaterThanOrEqualTo(4.5),
            reason: '${type.label}, tint $alpha',
          );
        }
      }
    }
  });

  test('light category icons remain distinct on their tinted circles', () {
    final surface = AppTheme.light().colorScheme.surfaceContainerLow;
    for (final type in MeterType.values) {
      final accent = meterColor(type, Brightness.light);
      final circle = Color.alphaBlend(accent.withValues(alpha: .12), surface);
      expect(_contrast(accent, circle), greaterThanOrEqualTo(3));
    }
    expect(
      meterColor(MeterType.electricity, Brightness.light),
      const Color(0xFF315E80),
    );
  });
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}
