import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/core/files/document_repository.dart';
import 'package:fahrzeugakte/core/files/photo_draft_store.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

class _Documents implements DocumentRepository {
  final deleted = <String>[];
  @override
  Future<DocumentImportResult> pick({bool multiple = true}) async =>
      DocumentImportResult(
        documents: [
          ReadingDocument(
            id: 'invoice',
            fileName: 'Rechnung.pdf',
            path: '/synthetic/invoice.pdf',
            sha256: 'a' * 64,
            pageCount: 2,
            sizeBytes: 10,
            source: DocumentSource.imported,
            addedAt: DateTime.utc(2026),
          ),
        ],
      );
  @override
  Future<DocumentImportResult> scan() => pick();
  @override
  Future<void> delete(String path) async => deleted.add(path);
}

Future<void> _tap(WidgetTester tester, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  ScaffoldMessenger.maybeOf(tester.element(finder))?.clearSnackBars();
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final discard in [false, true]) {
    testWidgets('PDF-only entry retains workshop and cost, discard=$discard', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final vehicle = sampleBook(label: 'Familienauto');
      final readings = MemoryReadingRepository();
      final documents = _Documents();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meterRepositoryProvider.overrideWithValue(
              MemoryMeterRepository()..items[vehicle.id] = vehicle,
            ),
            meterReadingRepositoryProvider.overrideWithValue(readings),
            evidenceExportRepositoryProvider.overrideWithValue(
              MemoryEvidenceExportRepository(),
            ),
            meterReminderRepositoryProvider.overrideWithValue(
              NoopMeterReminderRepository(),
            ),
            photoDraftStoreProvider.overrideWithValue(MemoryPhotoDraftStore()),
            documentRepositoryProvider.overrideWithValue(documents),
          ],
          child: const MeterReadingLogApp(),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'Familienauto');
      await _tap(tester, 'Eintrag erfassen');
      await _tap(tester, 'Dokument hinzufügen');
      await _tap(tester, 'PDFs auswählen');
      expect(find.text('Rechnung.pdf'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'Wartung',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Werkstatt (optional)'),
        'Musterwerkstatt',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kosten (optional)'),
        '249,90',
      );
      if (discard) {
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await _tap(tester, 'Eintrag verwerfen');
        expect(documents.deleted, ['/synthetic/invoice.pdf']);
        await _tap(tester, 'Ohne Foto erfassen');
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Werkstatt (optional)'),
              )
              .controller!
              .text,
          isEmpty,
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Kosten (optional)'),
              )
              .controller!
              .text,
          isEmpty,
        );
        expect(readings.items, isEmpty);
      } else {
        await _tap(tester, 'Eintrag bestätigen und speichern');
        for (var i = 0; i < 100 && readings.items.isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final saved = readings.items.values.single;
        expect(saved.hasPhoto, isFalse);
        expect(saved.hasMeasurement, isFalse);
        expect(saved.costCents, 24990);
        expect(saved.workshop, 'Musterwerkstatt');
        expect(saved.documents.single.id, 'invoice');
        expect(find.text('Rechnung.pdf'), findsOneWidget);
        expect(documents.deleted, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
