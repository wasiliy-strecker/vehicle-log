import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks the resolved glyph color against the widget's actual painted surfaces,
/// including translucent decorations over cards. Intended for solid UI surfaces,
/// not text over photos, gradients, or animated opacity.
void expectReadable(
  WidgetTester tester,
  Finder finder, {
  double minimum = 4.5,
}) {
  expect(finder, findsWidgets);
  final paragraphs = find.descendant(
    of: finder,
    matching: find.byType(RichText),
    matchRoot: true,
  );
  expect(paragraphs, findsWidgets);
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final foreground = paragraph.text.style?.color;
    expect(foreground, isNotNull);
    final layers = <Color>[];
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is DecoratedBox &&
          widget.position == DecorationPosition.background &&
          widget.decoration is BoxDecoration) {
        final color = (widget.decoration as BoxDecoration).color;
        if (color != null) layers.add(color);
      } else if (widget is ColoredBox) {
        layers.add(widget.color);
      } else if (widget is Material &&
          widget.type != MaterialType.transparency) {
        final theme = Theme.of(ancestor);
        layers.add(
          widget.color ??
              (widget.type == MaterialType.card
                  ? theme.cardColor
                  : theme.canvasColor),
        );
      }
      return true;
    });
    var background = Theme.of(element).scaffoldBackgroundColor;
    for (final layer in layers.reversed) {
      background = Color.alphaBlend(layer, background);
    }
    final visibleForeground = Color.alphaBlend(foreground!, background);
    final light = visibleForeground.computeLuminance();
    final dark = background.computeLuminance();
    final ratio = (math.max(light, dark) + .05) / (math.min(light, dark) + .05);
    expect(
      ratio,
      greaterThanOrEqualTo(minimum),
      reason:
          '${paragraph.text.toPlainText()}: $visibleForeground on $background',
    );
  }
}

void expectReadableContent(WidgetTester tester, Finder area) {
  expectReadable(
    tester,
    find.descendant(of: area, matching: find.byType(Text)),
  );
  final icons = find.descendant(of: area, matching: find.byType(Icon));
  if (icons.evaluate().isNotEmpty) {
    expectReadable(tester, icons, minimum: 3);
  }
}
