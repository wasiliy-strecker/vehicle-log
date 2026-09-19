import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/features/meters/presentation/first_registration_field.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

final _registration = find.widgetWithText(
  TextFormField,
  'Erstzulassung (optional)',
);

Future<void> _open(WidgetTester tester, MemoryMeterRepository meters) async {
  await tester.binding.setSurfaceSize(const Size(430, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        meterRepositoryProvider.overrideWithValue(meters),
        meterReadingRepositoryProvider.overrideWithValue(
          MemoryReadingRepository(),
        ),
        evidenceExportRepositoryProvider.overrideWithValue(
          MemoryEvidenceExportRepository(),
        ),
        meterReminderRepositoryProvider.overrideWithValue(
          NoopMeterReminderRepository(),
        ),
      ],
      child: const MeterReadingLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Familienauto'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fahrzeug & Erinnerung bearbeiten'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_registration);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, bool Function() saved) async {
  await tester.tap(find.text('Änderungen speichern'));
  for (var i = 0; i < 30 && !saved(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
  expect(saved(), isTrue);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'year-first picker saves a complete date without opening the keyboard',
    (tester) async {
      final vehicle = sampleBook(
        label: 'Familienauto',
      ).copyWith(firstRegistration: '03.2020');
      final meters = MemoryMeterRepository()..items[vehicle.id] = vehicle;
      await _open(tester, meters);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: _registration,
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await tester.tap(_registration);
      await tester.pumpAndSettle();
      expect(find.byType(YearPicker), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.text('2021'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17'));
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(_registration).controller!.text,
        '17.03.2021',
      );
      await _save(
        tester,
        () => meters.items[vehicle.id]!.firstRegistration == '17.03.2021',
      );
      expect(find.text('Erstzulassung: 17.03.2021'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling preserves month precision when saving another vehicle field',
    (tester) async {
      final vehicle = sampleBook(
        label: 'Familienauto',
      ).copyWith(firstRegistration: '03.2020');
      final meters = MemoryMeterRepository()..items[vehicle.id] = vehicle;
      await _open(tester, meters);
      await tester.tap(find.byTooltip('Erstzulassung auswählen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2019'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(_registration).controller!.text,
        '03.2020',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'FIN (optional)'),
        'SYNTHETIC000000001',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _save(
        tester,
        () => meters.items[vehicle.id]!.vin == 'SYNTHETIC000000001',
      );
      expect(meters.items[vehicle.id]!.firstRegistration, '03.2020');
    },
  );

  testWidgets('an optional registration date can be removed and saved', (
    tester,
  ) async {
    final vehicle = sampleBook(
      label: 'Familienauto',
    ).copyWith(firstRegistration: '29.02.2020');
    final meters = MemoryMeterRepository()..items[vehicle.id] = vehicle;
    await _open(tester, meters);
    await tester.tap(find.byTooltip('Erstzulassung entfernen'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(_registration).controller!.text,
      isEmpty,
    );
    await _save(
      tester,
      () => meters.items[vehicle.id]!.firstRegistration.isEmpty,
    );
  });

  test(
    'registration validation accepts legacy months and real calendar dates',
    () {
      for (final valid in ['', '03.2020', '17.03.2021', '29.02.2020']) {
        expect(firstRegistrationError(valid), isNull, reason: valid);
      }
      for (final invalid in [
        '31.04.2020',
        '29.02.2021',
        '00.2020',
        '13.2020',
        '00.01.2020',
      ]) {
        expect(firstRegistrationError(invalid), isNotNull, reason: invalid);
      }
    },
  );
}
