import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('wrapped action labels are centered in $brightness', (
      tester,
    ) async {
      final theme = brightness == Brightness.dark
          ? AppTheme.dark()
          : AppTheme.light();
      for (final labelText in ['Öffnen', 'Eine lange Beschriftung\nöffnen']) {
        for (final enabled in [true, false]) {
          final VoidCallback? action = enabled ? () {} : null;
          final label = Text(labelText);
          const icon = Icon(Icons.open_in_new);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(onPressed: action, child: label),
                        FilledButton.icon(
                          onPressed: action,
                          icon: icon,
                          label: label,
                        ),
                        OutlinedButton(onPressed: action, child: label),
                        OutlinedButton.icon(
                          onPressed: action,
                          icon: icon,
                          label: label,
                        ),
                        ElevatedButton(onPressed: action, child: label),
                        ElevatedButton.icon(
                          onPressed: action,
                          icon: icon,
                          label: label,
                        ),
                        TextButton(onPressed: action, child: label),
                        TextButton.icon(
                          onPressed: action,
                          icon: icon,
                          label: label,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final buttons = find.byWidgetPredicate((w) => w is ButtonStyleButton);
          expect(buttons, findsNWidgets(8));
          for (var i = 0; i < 8; i++) {
            final button = buttons.at(i);
            final text = find.descendant(
              of: button,
              matching: find.byType(Text),
            );
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.textAlign, TextAlign.center);
            expect(paragraph.didExceedMaxLines, isFalse);
            final rect = tester.getRect(button);
            var contents = tester.getRect(text);
            final glyph = find.descendant(
              of: button,
              matching: find.byType(Icon),
            );
            if (glyph.evaluate().isNotEmpty) {
              contents = contents.expandToInclude(tester.getRect(glyph));
            }
            expect(contents.center.dx, closeTo(rect.center.dx, 1));
            expect(rect.height, greaterThanOrEqualTo(56));
            // Check the visible button, not only its surrounding touch target.
            final material = find
                .descendant(of: button, matching: find.byType(Material))
                .first;
            expect(tester.getSize(material).height, greaterThanOrEqualTo(56));
            expect(paragraph.text.style?.fontSize, 16);
            expect(rect.contains(contents.topLeft), isTrue);
            expect(rect.contains(contents.bottomRight), isTrue);
          }
          expect(tester.takeException(), isNull);
        }
      }
    });
  }

  test('uses the same pill shape for all standard action buttons', () {
    final theme = AppTheme.light();

    expect(_shape(theme.filledButtonTheme.style), isA<StadiumBorder>());
    expect(_shape(theme.outlinedButtonTheme.style), isA<StadiumBorder>());
    expect(_shape(theme.elevatedButtonTheme.style), isA<StadiumBorder>());
    expect(_shape(theme.textButtonTheme.style), isA<StadiumBorder>());
  });

  test('uses the warm cream, Bordeaux and gold reading palette', () {
    final colors = AppTheme.light().colorScheme;

    expect(colors.surface, const Color(0xFFF1F4F7));
    expect(colors.surfaceContainerLow, const Color(0xFFFAFCFE));
    expect(colors.primary, const Color(0xFF315E80));
    expect(colors.secondary, const Color(0xFF536C81));
  });
}

OutlinedBorder? _shape(ButtonStyle? style) {
  return style?.shape?.resolve(const <WidgetState>{});
}
