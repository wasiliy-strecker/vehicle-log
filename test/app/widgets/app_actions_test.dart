import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app_theme.dart';
import 'package:fahrzeugakte/app/widgets/app_actions.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'all action types have 56px edge-tappable surfaces: $brightness',
      (tester) async {
        var taps = 0;
        void press() => taps++;
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: press,
                  icon: const Icon(Icons.add),
                  label: const Text('Speichern'),
                ),
                OutlinedButton(
                  onPressed: press,
                  child: const Text('Bearbeiten'),
                ),
                ElevatedButton(onPressed: press, child: const Text('Öffnen')),
                TextButton(onPressed: press, child: const Text('Fotohinweise')),
                const FilledButton(onPressed: null, child: Text('Deaktiviert')),
                IconButton(onPressed: press, icon: const Icon(Icons.settings)),
              ],
            ),
          ),
        );
        for (final label in [
          'Speichern',
          'Bearbeiten',
          'Öffnen',
          'Fotohinweise',
          'Deaktiviert',
        ]) {
          final button = find
              .ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              )
              .first;
          final material = find
              .descendant(of: button, matching: find.byType(Material))
              .first;
          final rect = tester.getRect(material);
          expect(rect.height, 56, reason: label);
          final style = DefaultTextStyle.of(
            tester.element(find.text(label)),
          ).style;
          expect(style.fontSize, 16);
          expect(style.fontWeight, FontWeight.w600);
          await tester.tapAt(Offset(rect.left + 2, rect.center.dy));
        }
        expect(taps, 4, reason: 'The disabled action must stay disabled');
        final icon = find.byType(IconButton);
        final iconRect = tester.getRect(icon);
        expect(iconRect.height, greaterThanOrEqualTo(48));
        expect(iconRect.width, greaterThanOrEqualTo(48));
        await tester.tapAt(Offset(iconRect.center.dx, iconRect.top + 2));
        expect(taps, 5);
        expect(IconTheme.of(tester.element(find.byIcon(Icons.add))).size, 22);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('long action text grows without clipping at scale $scale', (
      tester,
    ) async {
      _screen(tester, const Size(320, 800));
      var tapped = false;
      const label = 'Fahrzeug & Erinnerung bearbeiten';
      await tester.pumpWidget(
        _app(
          scale: scale,
          child: Align(
            alignment: Alignment.topCenter,
            child: OutlinedButton.icon(
              onPressed: () => tapped = true,
              icon: const Icon(Icons.edit_outlined),
              label: const Text(label),
            ),
          ),
        ),
      );
      final button = find.byType(OutlinedButton);
      final rect = tester.getRect(button);
      final text = tester.getRect(find.text(label));
      expect(rect.height, greaterThanOrEqualTo(56 - 0.001));
      expect(rect.contains(text.topLeft), isTrue);
      expect(rect.contains(text.bottomRight), isTrue);
      expect(rect.right, lessThanOrEqualTo(320));
      if (scale == 2) expect(rect.height, greaterThan(56));
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, scale, stacked) in [
    (319.0, 1.0, true),
    (320.0, 1.0, false),
    (400.0, 1.5, true),
    (320.0, 2.0, true),
  ]) {
    testWidgets('action pairs remain usable at width $width and scale $scale', (
      tester,
    ) async {
      _screen(tester, Size(width + 32, 800));
      final actions = <String>[];
      await tester.pumpWidget(
        _app(
          scale: scale,
          child: AppActionRow(
            children: [
              OutlinedButton.icon(
                onPressed: () => actions.add('print'),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Drucken'),
              ),
              FilledButton.icon(
                onPressed: () => actions.add('share'),
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Teilen'),
              ),
            ],
          ),
        ),
      );
      final first = tester.getRect(find.byType(OutlinedButton));
      final second = tester.getRect(find.byType(FilledButton));
      if (stacked) {
        expect(second.top - first.bottom, 12);
        expect(first.width, width);
        expect(second.width, width);
      } else {
        expect(first.top, second.top);
        expect(second.left - first.right, 12);
      }
      await tester.tap(find.text('Drucken'));
      await tester.tap(find.text('Teilen'));
      expect(actions, ['print', 'share']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final label in ['Fahrzeug anlegen', 'Eintrag erfassen']) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('floating $label fits a narrow phone at scale $scale', (
        tester,
      ) async {
        _screen(tester, const Size(320, 800));
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: ListView(
                  padding: EdgeInsets.only(
                    bottom: AppFloatingActionButton.contentBottomPadding(
                      context,
                      label,
                    ),
                  ),
                  children: const [
                    SizedBox(height: 1000),
                    Text('Letzter Eintrag'),
                  ],
                ),
                floatingActionButton: AppFloatingActionButton(
                  onPressed: () => taps++,
                  icon: Icons.add,
                  label: label,
                ),
              ),
            ),
          ),
        );
        final button = find.byType(FloatingActionButton);
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(16 - .001));
        expect(rect.right, lessThanOrEqualTo(304 + .001));
        expect(rect.height, greaterThanOrEqualTo(56 - 0.001));
        expect(
          rect.contains(tester.getRect(find.text(label)).bottomRight),
          isTrue,
        );
        await tester.drag(find.byType(ListView), const Offset(0, -1500));
        await tester.pumpAndSettle();
        expect(
          tester.getBottomRight(find.text('Letzter Eintrag')).dy,
          lessThan(rect.top),
        );
        await tester.tapAt(Offset(rect.center.dx, rect.top + 2));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Widget _app({
  required Widget child,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void _screen(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
