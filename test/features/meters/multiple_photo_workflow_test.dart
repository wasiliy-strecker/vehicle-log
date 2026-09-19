import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/app/app_theme.dart';
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_photo_gallery.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  testWidgets(
    'manual entry can remove all drafts and later add, remove and sort saved photos',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final meter = sampleBook();
      final readings = MemoryReadingRepository();
      final photos = _Photos();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialPhotoDraftRouteProvider.overrideWithValue(
              '/meter/${meter.id}/capture',
            ),
            meterRepositoryProvider.overrideWithValue(
              MemoryMeterRepository()..items[meter.id] = meter,
            ),
            meterReadingRepositoryProvider.overrideWithValue(readings),
            evidenceExportRepositoryProvider.overrideWithValue(
              MemoryEvidenceExportRepository(),
            ),
            meterPhotoCaptureRepositoryProvider.overrideWithValue(photos),
            evidencePhotoAssetRepositoryProvider.overrideWithValue(
              const NoopEvidencePhotoAssetRepository(),
            ),
            meterReminderRepositoryProvider.overrideWithValue(
              NoopMeterReminderRepository(),
            ),
          ],
          child: const MeterReadingLogApp(),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'Ohne Foto erfassen');
      await tester.ensureVisible(find.byKey(const ValueKey('care-activity')));
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'Kilometerstand',
      );
      final value = find.widgetWithText(
        TextFormField,
        'Kilometerstand (optional)',
      );
      await tester.enterText(value, '12');
      FocusManager.instance.primaryFocus?.unfocus();
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      await _photoAction(tester, 2, 'Foto entfernen');
      expect(find.text('Aktuelle Fotos (1)'), findsOneWidget);
      await _photoAction(tester, 1, 'Foto entfernen');
      expect(find.text('Aktuelle Fotos (0)'), findsOneWidget);
      expect(tester.widget<TextFormField>(value).controller!.text, '12');
      expect(photos.deleted, ['/photo2.jpg', '/photo1.jpg']);
      await _tap(tester, 'Eintrag speichern');
      await _wait(tester, () => readings.items.isNotEmpty);
      final manual = readings.items.values.single;
      expect(manual.currentPhotos, isEmpty);
      expect(manual.photoHistory, isEmpty);

      await _tap(tester, 'Bearbeiten');
      await _tap(tester, 'Foto aufnehmen');
      await _tap(tester, 'Änderungen speichern');
      await _wait(tester, () => readings.items.values.single.hasPhoto);
      final single = readings.items.values.single;
      expect(single.currentPhotos, hasLength(1));
      expect(single.photoHistory, isEmpty);
      await _tap(tester, 'Bearbeiten');
      await _photoAction(tester, 1, 'Foto entfernen');
      await _tap(tester, 'Änderungen speichern');
      await _wait(tester, () => !readings.items.values.single.hasPhoto);
      expect(readings.items.values.single.photoHistory, isEmpty);
      expect(photos.deleted, contains('/photo3.jpg'));

      await _tap(tester, 'Bearbeiten');
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      await _photoAction(tester, 2, 'Nach vorne');
      await _tap(tester, 'Änderungen speichern');
      await _wait(
        tester,
        () => readings.items.values.single.currentPhotos.length == 2,
      );
      final saved = readings.items.values.single;
      expect(saved.currentPhotos.map((p) => p.path), [
        '/photo5.jpg',
        '/photo4.jpg',
      ]);
      expect(saved.photoHistory, isEmpty);
      expect(saved.value.displayText, '12');
      expect(saved.capturedAt, manual.capturedAt);
      expect(await readings.loadRevisions(saved.id), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'capture mixed photos, browse them, replace one, remove one and add more',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final meter = sampleBook(label: 'Mein Schal');
      final readings = MemoryReadingRepository();
      final photos = _Photos();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meterRepositoryProvider.overrideWithValue(
              MemoryMeterRepository()..items[meter.id] = meter,
            ),
            meterReadingRepositoryProvider.overrideWithValue(readings),
            evidenceExportRepositoryProvider.overrideWithValue(
              MemoryEvidenceExportRepository(),
            ),
            meterPhotoCaptureRepositoryProvider.overrideWithValue(photos),
            evidencePhotoAssetRepositoryProvider.overrideWithValue(
              const NoopEvidencePhotoAssetRepository(),
            ),
            meterReminderRepositoryProvider.overrideWithValue(
              NoopMeterReminderRepository(),
            ),
          ],
          child: const MeterReadingLogApp(),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'Mein Schal');
      await _tap(tester, 'Eintrag erfassen');
      await _tap(tester, 'Fahrzeug fotografieren');
      await _tap(tester, 'Weiteres Foto aufnehmen');
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      expect(find.text('Aktuelle Fotos (4)'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('care-activity')));
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'Kilometerstand',
      );
      final value = find.widgetWithText(
        TextFormField,
        'Kilometerstand (optional)',
      );
      await tester.ensureVisible(value);
      await tester.enterText(value, '25');
      FocusManager.instance.primaryFocus?.unfocus();
      await _tap(tester, 'Eintrag bestätigen und speichern');
      await _wait(tester, () => readings.items.isNotEmpty);
      final first = readings.items.values.single;
      expect(first.currentPhotos, hasLength(4));
      expect(first.currentPhotos.map((p) => p.source), [
        ReadingSource.camera,
        ReadingSource.camera,
        ReadingSource.gallery,
        ReadingSource.gallery,
      ]);
      final image = find
          .descendant(
            of: find.byType(ReadingPhotoGallery),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(image);
      await tester.tap(image);
      await tester.pumpAndSettle();
      expect(find.text('Foto 1 von 4'), findsOneWidget);
      await tester.tap(find.byTooltip('Nächstes Foto'));
      await tester.pumpAndSettle();
      expect(find.text('Foto 2 von 4'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsWidgets);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      await _tap(tester, 'Bearbeiten');
      await _photoAction(tester, 2, 'Foto ersetzen');
      await _tap(tester, 'Aus Galerie wählen');
      await _photoAction(tester, 3, 'Foto entfernen');
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      await _tap(tester, 'Änderungen speichern');
      await _wait(
        tester,
        () => readings.items.values.single.currentPhotos.length == 5,
      );
      final corrected = readings.items.values.single;
      expect(corrected.value.displayText, '25');
      expect(corrected.capturedAt, first.capturedAt);
      expect(corrected.currentPhotos.first.id, first.currentPhotos.first.id);
      expect(corrected.photoHistory, isEmpty);
      expect(await readings.loadRevisions(first.id), isEmpty);
      expect(
        photos.deleted,
        unorderedEquals([
          first.currentPhotos[1].path,
          first.currentPhotos[2].path,
        ]),
      );
      await _tap(tester, 'Bearbeiten');
      await _tap(tester, 'Weiteres Foto aufnehmen');
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      await _tap(tester, 'Änderungen verwerfen');
      expect(readings.items.values.single.toJson(), corrected.toJson());
      expect(
        photos.deleted,
        unorderedEquals([
          first.currentPhotos[1].path,
          first.currentPhotos[2].path,
          '/photo8.jpg',
        ]),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'multi photo editor fits narrow phone and large type in $brightness',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final photo = sampleReading().currentPhotos.single;
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? AppTheme.dark()
                : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReadingPhotoEditor(
                  photos: [photo, photo, photo],
                  busy: false,
                  onCamera: () {},
                  onGallery: () {},
                  onReplace: (_) {},
                  onRemove: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _tap(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _photoAction(WidgetTester tester, int index, String action) async {
  final button = find.byTooltip('Foto $index bearbeiten');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await _tap(tester, action);
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(ready(), true);
}

class _Photos extends UnsupportedMeterPhotoCaptureRepository
    implements MultiPhotoCaptureRepository {
  var count = 0;
  final deleted = <String>[];
  StoredMeterPhoto _next(ReadingSource source) => StoredMeterPhoto(
    path: '/photo${++count}.jpg',
    sha256: count.toString().padLeft(64, '0'),
    source: source,
    capturedAt: DateTime.utc(2026, 9, 17),
  );
  @override
  Future<StoredMeterPhoto?> capture(ReadingSource source) async =>
      _next(source);
  @override
  Future<PhotoImportResult> pickGalleryPhotos({
    PhotoImportProgress? onProgress,
  }) async => PhotoImportResult(
    photos: [_next(ReadingSource.gallery), _next(ReadingSource.gallery)],
  );
  @override
  Future<PhotoImportResult> recoverPhotos({
    required ReadingSource source,
    PhotoImportProgress? onProgress,
  }) async => const PhotoImportResult();
  @override
  Future<void> delete(String path) async {
    deleted.add(path);
  }
}
