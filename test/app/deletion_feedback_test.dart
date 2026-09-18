import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/app/app_router.dart';
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';

import '../support/fakes.dart';
import '../support/reading_fixtures.dart';

void main() {
  for (final deleteReading in [false, true]) {
    final subject = deleteReading ? 'Fahrzeugeintrag' : 'Fahrzeug';
    testWidgets('$subject deletion reports cancellation, failure and success', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final meters = _Meters()..items['meter'] = sampleBook(id: 'meter');
      final readings = _Readings();
      if (deleteReading) {
        readings.items['reading'] = sampleReading(book: meters.items['meter']!);
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meterRepositoryProvider.overrideWithValue(meters),
            meterReadingRepositoryProvider.overrideWithValue(readings),
            evidenceExportRepositoryProvider.overrideWithValue(
              MemoryEvidenceExportRepository(),
            ),
            meterReminderRepositoryProvider.overrideWithValue(
              NoopMeterReminderRepository(),
            ),
            meterPhotoCaptureRepositoryProvider.overrideWithValue(
              const UnsupportedMeterPhotoCaptureRepository(),
            ),
            evidencePhotoAssetRepositoryProvider.overrideWithValue(
              const NoopEvidencePhotoAssetRepository(),
            ),
          ],
          child: const MeterReadingLogApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = ProviderScope.containerOf(
        tester.element(find.byType(MeterReadingLogApp)),
      ).read(appRouterProvider);
      router.pushNamed('meterDetail', pathParameters: {'id': 'meter'});
      await tester.pumpAndSettle();
      if (deleteReading) {
        router.pushNamed('readingDetail', pathParameters: {'id': 'reading'});
        await tester.pumpAndSettle();
      }
      final originalRoute = router.state.uri.path;
      final delete = find.widgetWithText(
        OutlinedButton,
        deleteReading ? 'Eintrag löschen' : 'Fahrzeug löschen',
      );
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Abbrechen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, originalRoute);
      expect(find.text('$subject gelöscht.'), findsNothing);

      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, originalRoute);
      expect(
        find.text(
          '$subject konnte nicht vollständig gelöscht werden. Bitte versuche es erneut.',
        ),
        findsOneWidget,
      );
      expect(find.text('$subject gelöscht.'), findsNothing);
      expect(meters.items, contains('meter'));
      if (deleteReading) expect(readings.items, contains('reading'));

      meters.fail = false;
      readings.fail = false;
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, deleteReading ? '/meter/meter' : '/');
      expect(find.text('$subject gelöscht.'), findsOneWidget);
      expect(deleteReading ? readings.items : meters.items, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Meters extends MemoryMeterRepository {
  bool fail = true;

  @override
  Future<void> delete(String id) async {
    if (fail) throw StateError('Synthetic deletion failure');
    await super.delete(id);
  }
}

class _Readings extends MemoryReadingRepository {
  bool fail = true;

  @override
  Future<void> delete(String id) async {
    if (fail) throw StateError('Synthetic deletion failure');
    await super.delete(id);
  }
}
