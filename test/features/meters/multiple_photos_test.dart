import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

ReadingPhotoVersion testPhoto(String id, {String? hash}) => ReadingPhotoVersion(
  id: id,
  path: '/$id.jpg',
  sha256: hash ?? id.padRight(64, 'a'),
  source: ReadingSource.gallery,
  addedAt: DateTime.utc(2026, 9, 17),
  ocrRawText: '',
  ocrCandidate: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reordering persists unchanged photo IDs without archiving or deleting files',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final meters = DriftMeterRepository(db);
      final readings = DriftMeterReadingRepository(db);
      final photos = _Photos();
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: DriftEvidenceExportRepository(db),
        photos: photos,
        reminders: NoopMeterReminderRepository(),
      );
      final meter = sampleBook();
      await meters.save(meter);
      final original = await service.createWithPhotos(
        meter: meter,
        photos: [testPhoto('a'), testPhoto('b'), testPhoto('c')],
        value: ReadingValue.tryParseWhole('35')!,
        capturedAt: DateTime.utc(2026, 9, 16),
        note: 'Unverändert',
      );
      final updated = await service.update(
        existing: original,
        value: original.value,
        capturedAt: original.capturedAt,
        note: original.note,
        photos: [original.currentPhotos[2], ...original.currentPhotos.take(2)],
      );
      final loaded = (await readings.findById(original.id))!;
      expect(loaded.currentPhotos.map((p) => p.id), ['c', 'a', 'b']);
      expect(loaded.photoPath, '/c.jpg');
      expect(loaded.photoHistory, isEmpty);
      expect(loaded.currentPhotos.map((p) => p.toJson()), [
        original.currentPhotos[2].toJson(),
        original.currentPhotos[0].toJson(),
        original.currentPhotos[1].toJson(),
      ]);
      expect(loaded.manifestSha256, isNot(original.manifestSha256));
      expect(loaded.value, original.value);
      expect(loaded.capturedAt, original.capturedAt);
      expect(loaded.note, original.note);
      expect(await readings.loadRevisions(original.id), isEmpty);
      expect(photos.deleted, isEmpty);
      await service.update(
        existing: updated,
        value: updated.value,
        capturedAt: updated.capturedAt,
        note: updated.note,
        photos: updated.currentPhotos,
      );
      expect(await readings.loadRevisions(original.id), isEmpty);
    },
  );
  test(
    'ordered photos survive individual corrections, removal and database reload',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final meters = DriftMeterRepository(db);
      final readings = DriftMeterReadingRepository(db);
      final photos = _Photos();
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: DriftEvidenceExportRepository(db),
        photos: photos,
        reminders: NoopMeterReminderRepository(),
      );
      final meter = sampleBook();
      await meters.save(meter);
      final original = await service.createWithPhotos(
        meter: meter,
        photos: [testPhoto('a'), testPhoto('b'), testPhoto('c')],
        value: ReadingValue.tryParseWhole('25')!,
        capturedAt: DateTime.utc(2026, 9, 16),
        note: 'Ärmel',
      );
      var loaded = (await readings.findById(original.id))!;
      expect(loaded.currentPhotos.map((p) => p.id), ['a', 'b', 'c']);
      final corrected = await service.update(
        existing: loaded,
        value: loaded.value,
        capturedAt: loaded.capturedAt,
        note: loaded.note,
        photos: [
          loaded.currentPhotos.first,
          testPhoto('d', hash: testPhoto('b').sha256),
          loaded.currentPhotos.last,
          testPhoto('e'),
        ],
      );
      expect(corrected.currentPhotos.map((p) => p.id), ['a', 'd', 'c', 'e']);
      expect(corrected.photoHistory, isEmpty);
      expect(corrected.value.displayText, '25');
      expect(corrected.capturedAt, original.capturedAt);
      expect(await readings.loadRevisions(original.id), isEmpty);
      loaded = (await readings.findById(original.id))!;
      expect(loaded.toJson(), corrected.toJson());
      await service.update(
        existing: loaded,
        value: loaded.value,
        capturedAt: loaded.capturedAt,
        note: loaded.note,
        photos: loaded.currentPhotos,
      );
      expect(await readings.loadRevisions(original.id), isEmpty);
      final empty = await service.update(
        existing: loaded,
        value: loaded.value,
        capturedAt: loaded.capturedAt,
        note: loaded.note,
        photos: [],
      );
      expect(empty.hasPhoto, false);
      expect(empty.currentPhotos, isEmpty);
      expect(empty.allPhotoVersions, isEmpty);
      expect(photos.deleted.toSet(), {
        '/a.jpg',
        '/b.jpg',
        '/c.jpg',
        '/d.jpg',
        '/e.jpg',
      });
      await service.delete(empty);
      expect(photos.deleted.toSet(), {
        '/a.jpg',
        '/b.jpg',
        '/c.jpg',
        '/d.jpg',
        '/e.jpg',
      });
    },
  );

  test(
    'legacy representation retains its hash and empty collections stay empty',
    () async {
      const integrity = IntegrityService();
      final legacy = sampleReading();
      final json = legacy.toJson();
      expect(json.containsKey('photos'), false);
      final loaded = MeterReading.fromJson(json);
      expect(loaded.currentPhotos.single.path, legacy.photoPath);
      expect(
        await integrity.readingManifestHash(loaded),
        await integrity.readingManifestHash(legacy),
      );
      final removed = MeterReading.fromJson({...json, 'photos': <Object>[]});
      expect(removed.currentPhotos, isEmpty);
      expect(removed.hasPhoto, false);
    },
  );

  test(
    'collection hashes include every photo and order but exclude local paths',
    () async {
      const integrity = IntegrityService();
      final reading = sampleReading().copyWith(
        photos: [testPhoto('a'), testPhoto('b')],
      );
      final relocated = reading.copyWith(
        photos: reading.currentPhotos
            .map((p) => p.copyWith(path: '/restored/${p.id}.jpg'))
            .toList(),
      );
      final reversed = reading.copyWith(
        photos: reading.currentPhotos.reversed.toList(),
      );
      final changed = reading.copyWith(
        photos: [
          testPhoto('a'),
          testPhoto('b', hash: 'f' * 64),
        ],
      );
      final hash = await integrity.readingManifestHash(reading);
      expect(await integrity.readingManifestHash(relocated), hash);
      expect(await integrity.readingManifestHash(reversed), isNot(hash));
      expect(await integrity.readingManifestHash(changed), isNot(hash));
    },
  );
}

class _Photos extends UnsupportedMeterPhotoCaptureRepository {
  final deleted = <String>[];
  @override
  Future<void> delete(String path) async {
    deleted.add(path);
  }
}
