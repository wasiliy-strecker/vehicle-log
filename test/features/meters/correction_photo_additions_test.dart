import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/files/photo_draft_store.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_photo_gallery.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';
import 'multiple_photos_test.dart' show testPhoto;

void main() {
  final cases = {
    'no photos': sampleReading(source: ReadingSource.manual),
    'legacy single photo': sampleReading(),
    'multiple current photos': sampleReading().copyWith(
      photos: [testPhoto('existing-a'), testPhoto('existing-b')],
    ),
    'historical photos only': sampleReading(
      source: ReadingSource.manual,
    ).copyWith(photos: [], photoHistory: [testPhoto('archived')]),
  };

  for (final entry in cases.entries) {
    testWidgets('correction appends two gallery batches to ${entry.key}', (
      tester,
    ) async {
      final original = entry.value.copyWith(note: 'Notiz bleibt erhalten');
      final rig = await _open(tester, original);
      final initialCount = original.currentPhotos.length;
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      expect(find.text('Aktuelle Fotos (${initialCount + 3})'), findsOneWidget);
      rig.photos.batchSize = 2;
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      expect(find.text('Aktuelle Fotos (${initialCount + 5})'), findsOneWidget);
      expect(rig.photos.galleryCalls, 2);
      expect(rig.photos.singleCalls, 0);
      final pending = tester
          .widget<ReadingPhotoEditor>(find.byType(ReadingPhotoEditor))
          .photos
          .toList();
      expect(pending.map((p) => p.path), [
        ...original.currentPhotos.map((p) => p.path),
        for (var i = 1; i <= 5; i++) '/added-$i.jpg',
      ]);
      expect((await rig.load(tester)).toJson(), original.toJson());

      await tester.pump(const Duration(seconds: 5));
      await _tap(tester, 'Korrektur protokollieren');
      await _waitFor(tester, find.text('Korrektur protokolliert.'));
      final saved = await rig.load(tester);
      expect(
        saved.currentPhotos.map((p) => p.toJson()),
        pending.map((p) => p.toJson()),
      );
      expect(saved.value, original.value);
      expect(saved.capturedAt, original.capturedAt);
      expect(saved.timezoneOffsetMinutes, original.timezoneOffsetMinutes);
      expect(saved.note, original.note);
      expect(
        saved.photoHistory.map((p) => p.toJson()),
        original.photoHistory.map((p) => p.toJson()),
      );
      final revisions = await tester.runAsync(
        () => rig.readings.loadRevisions(original.id),
      );
      expect(revisions, hasLength(1));
      expect(revisions!.single.changes, isEmpty);
      expect(
        revisions.single.photoChange!.beforeIds,
        original.currentPhotos.map((p) => p.id),
      );
      expect(revisions.single.photoChange!.afterIds, pending.map((p) => p.id));
      final expectedHash = await tester.runAsync(
        () => const IntegrityService().readingManifestHash(saved),
      );
      expect(saved.manifestSha256, expectedHash);
      expect(rig.photos.deleted, isEmpty);
      expect(await rig.drafts.read('/reading/${original.id}/edit'), null);

      await _tap(tester, 'Korrigieren');
      await _waitFor(tester, find.byType(ReadingPhotoEditor));
      expect(
        tester
            .widget<ReadingPhotoEditor>(find.byType(ReadingPhotoEditor))
            .photos
            .map((p) => p.id),
        pending.map((p) => p.id),
      );
      expect(tester.takeException(), isNull);
      await rig.close(tester);
    });
  }

  testWidgets(
    'failed correction save keeps the entire batch for a single retry',
    (tester) async {
      final original = sampleReading().copyWith(
        photoHistory: [testPhoto('archived')],
      );
      final rig = await _open(tester, original);
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      final pending = tester
          .widget<ReadingPhotoEditor>(find.byType(ReadingPhotoEditor))
          .photos
          .toList();
      rig.readings.failNextUpdate = true;
      await _tap(tester, 'Korrektur protokollieren');
      await _waitFor(tester, find.textContaining('Korrektur fehlgeschlagen:'));
      expect((await rig.load(tester)).toJson(), original.toJson());
      expect(
        await tester.runAsync(() => rig.readings.loadRevisions(original.id)),
        isEmpty,
      );
      expect(
        tester
            .widget<ReadingPhotoEditor>(find.byType(ReadingPhotoEditor))
            .photos
            .map((p) => p.id),
        pending.map((p) => p.id),
      );
      expect(rig.photos.deleted, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await _tap(tester, 'Korrektur protokollieren');
      await _waitFor(tester, find.text('Korrektur protokolliert.'));
      expect(
        (await rig.load(tester)).currentPhotos.map((p) => p.id),
        pending.map((p) => p.id),
      );
      expect(
        await tester.runAsync(() => rig.readings.loadRevisions(original.id)),
        hasLength(1),
      );
      expect(rig.photos.galleryCalls, 1);
      expect(rig.photos.deleted, isEmpty);
      expect(tester.takeException(), isNull);
      await rig.close(tester);
    },
  );

  testWidgets(
    'cancelled picker retains additions and discarding deletes only the new batch',
    (tester) async {
      final original = sampleReading().copyWith(
        photoHistory: [testPhoto('archived')],
      );
      final rig = await _open(tester, original);
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      rig.photos.batchSize = 0;
      await _tap(tester, 'Fotos aus Galerie hinzufügen');
      expect(find.text('Aktuelle Fotos (4)'), findsOneWidget);
      expect(rig.photos.deleted, isEmpty);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      await _tap(tester, 'Korrektur verwerfen');
      await _waitFor(tester, find.text('Korrigieren'));
      expect((await rig.load(tester)).toJson(), original.toJson());
      expect(
        await tester.runAsync(() => rig.readings.loadRevisions(original.id)),
        isEmpty,
      );
      expect(rig.photos.deleted, [
        '/added-1.jpg',
        '/added-2.jpg',
        '/added-3.jpg',
      ]);
      expect(await rig.drafts.read('/reading/${original.id}/edit'), null);
      expect(tester.takeException(), isNull);
      await rig.close(tester);
    },
  );
}

Future<_Rig> _open(WidgetTester tester, MeterReading original) async {
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final db = AppDatabase.memory();
  final rig = _Rig(db, original.id);
  addTearDown(() => rig.closed ? Future<void>.value() : db.close());
  final meters = DriftMeterRepository(db);
  await tester.runAsync(() async {
    await meters.save(sampleBook());
    await rig.readings.save(original);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialPhotoDraftRouteProvider.overrideWithValue(
          '/reading/${original.id}/edit',
        ),
        meterRepositoryProvider.overrideWithValue(meters),
        meterReadingRepositoryProvider.overrideWithValue(rig.readings),
        evidenceExportRepositoryProvider.overrideWithValue(
          DriftEvidenceExportRepository(db),
        ),
        meterPhotoCaptureRepositoryProvider.overrideWithValue(rig.photos),
        photoDraftStoreProvider.overrideWithValue(rig.drafts),
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
  await _waitFor(tester, find.byType(ReadingPhotoEditor));
  return rig;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder.last);
  await tester.pumpAndSettle();
  await tester.tap(finder.last);
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(finder, findsOneWidget);
}

class _Rig {
  _Rig(this.db, this.readingId) : readings = _Readings(db);
  final AppDatabase db;
  bool closed = false;
  final String readingId;
  final _Readings readings;
  final photos = _Photos();
  final drafts = MemoryPhotoDraftStore();
  Future<MeterReading> load(WidgetTester tester) async =>
      (await tester.runAsync(() => readings.findById(readingId)))!;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
    closed = true;
  }
}

class _Readings extends DriftMeterReadingRepository {
  _Readings(super.database);
  bool failNextUpdate = false;
  @override
  Future<void> updateWithRevision(
    MeterReading reading,
    ReadingRevision revision,
  ) async {
    if (failNextUpdate) {
      failNextUpdate = false;
      throw StateError('Simulated write failure');
    }
    await super.updateWithRevision(reading, revision);
  }
}

class _Photos extends UnsupportedMeterPhotoCaptureRepository
    implements MultiPhotoCaptureRepository {
  int batchSize = 3;
  int galleryCalls = 0;
  int singleCalls = 0;
  int count = 0;
  final deleted = <String>[];
  @override
  Future<StoredMeterPhoto?> capture(ReadingSource source) async {
    singleCalls++;
    throw StateError('Adding gallery photos must use multiple selection');
  }

  @override
  Future<PhotoImportResult> pickGalleryPhotos({
    PhotoImportProgress? onProgress,
  }) async {
    galleryCalls++;
    return PhotoImportResult(
      photos: [
        for (var i = 0; i < batchSize; i++)
          StoredMeterPhoto(
            path: '/added-${++count}.jpg',
            sha256: count.toString().padLeft(64, '0'),
            source: ReadingSource.gallery,
            capturedAt: DateTime.utc(2026, 9, 17),
          ),
      ],
    );
  }

  @override
  Future<PhotoImportResult> recoverPhotos({
    required ReadingSource source,
    PhotoImportProgress? onProgress,
  }) async => const PhotoImportResult();
  @override
  Future<void> delete(String path) async => deleted.add(path);
}
