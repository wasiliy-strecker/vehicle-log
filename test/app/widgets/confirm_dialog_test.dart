import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/widgets/confirm_dialog.dart';
import 'package:fahrzeugakte/app/app_theme.dart';

void main() {
  for (final discard in [false, true]) {
    testWidgets(
      'large-text confirmation stays scrollable and cancelable: $discard',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 700);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () async {
                    result = discard
                        ? await confirmDiscardChanges(
                            context,
                            title: 'Änderungen verwerfen?',
                            message:
                                'Die Änderungen an diesem Eintrag wurden noch nicht gespeichert.',
                          )
                        : await confirmDestructiveAction(
                            context,
                            title: 'Fahrzeug löschen?',
                            message:
                                'Das Buch mit allen Einträgen, Fotos und gespeicherten Fahrzeugprotokollen wird dauerhaft gelöscht.',
                          );
                  },
                  child: const Text('Öffnen'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Öffnen'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cancel = find.widgetWithText(
          OutlinedButton,
          discard ? 'Weiter bearbeiten' : 'Abbrechen',
        );
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        final rect = tester.getRect(cancel);
        expect(rect.height, greaterThanOrEqualTo(56));
        await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
        await tester.pumpAndSettle();
        expect(result, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('destructive confirmation uses stacked full-width actions', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await confirmDestructiveAction(
                  context,
                  title: 'Eintrag löschen?',
                  message: 'Dieser Eintrag wird dauerhaft gelöscht.',
                );
              },
              child: const Text('Dialog öffnen'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Dialog öffnen'));
    await tester.pumpAndSettle();

    final confirmButton = find.widgetWithText(FilledButton, 'Löschen');
    final cancelButton = find.widgetWithText(OutlinedButton, 'Abbrechen');
    expect(confirmButton, findsOneWidget);
    expect(cancelButton, findsOneWidget);
    expect(
      tester.getSize(confirmButton).width,
      tester.getSize(cancelButton).width,
    );
    expect(
      tester.getTopLeft(confirmButton).dy,
      lessThan(tester.getTopLeft(cancelButton).dy),
    );

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets(
    'discard confirmation keeps editing unless explicitly discarded',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await confirmDiscardChanges(
                    context,
                    title: 'Änderungen verwerfen?',
                    message: 'Die Änderungen wurden noch nicht gespeichert.',
                  );
                },
                child: const Text('Dialog öffnen'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Dialog öffnen'));
      await tester.pumpAndSettle();

      final discard = find.widgetWithText(FilledButton, 'Änderungen verwerfen');
      final keepEditing = find.widgetWithText(
        OutlinedButton,
        'Weiter bearbeiten',
      );
      expect(discard, findsOneWidget);
      expect(keepEditing, findsOneWidget);
      expect(tester.getSize(discard).width, tester.getSize(keepEditing).width);

      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );
}
