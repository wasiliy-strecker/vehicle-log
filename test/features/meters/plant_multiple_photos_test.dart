import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all care actions retain optional height across photos and backup',
    () async {
      final temp = await Directory.systemTemp.createTemp('plant_multi_photo_');
      addTearDown(() => temp.delete(recursive: true));
      final database = AppDatabase.memory();
      addTearDown(database.close);
      final meters = DriftMeterRepository(database);
      final readings = DriftMeterReadingRepository(database);
      final exports = DriftEvidenceExportRepository(database);
      final reminders = NoopMeterReminderRepository();
      const integrity = IntegrityService();
      final plant = sampleBook(label: 'Testfahrzeug').copyWith(unit: 'mm');
      await meters.save(plant);
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: exports,
        photos: const UnsupportedMeterPhotoCaptureRepository(),
        reminders: reminders,
      );
      final expected = <MeterReading>[];
      for (final activity in CareActivity.presets) {
        for (final measured in [false, true]) {
          final photos = <ReadingPhotoVersion>[];
          for (var index = 0; index < 3; index++) {
            final id = '${activity.name}_${measured}_$index';
            final file = File('${temp.path}/$id.jpg')
              ..writeAsBytesSync([activity.index, measured ? 1 : 0, index]);
            photos.add(
              ReadingPhotoVersion(
                id: id,
                path: file.path,
                sha256: await integrity.sha256Bytes(await file.readAsBytes()),
                source: ReadingSource.gallery,
                addedAt: DateTime.utc(2026, 9, 17),
                ocrRawText: '',
                ocrCandidate: '',
              ),
            );
          }
          final original = await service.createWithPhotos(
            meter: plant,
            photos: photos.take(2).toList(),
            value: ReadingValue.tryParseWhole('42')!,
            activity: activity,
            hasMeasurement: measured,
            capturedAt: DateTime.utc(
              2026,
              9,
              17,
              activity.index,
              measured ? 1 : 0,
            ),
            note: 'Pflege mit mehreren Fotos',
          );
          final updated = await service.update(
            existing: original,
            photos: [photos[1], photos[2]],
            value: original.value,
            capturedAt: original.capturedAt,
            note: original.note,
          );
          final loaded = (await readings.findById(updated.id))!;
          expect(loaded.toJson(), updated.toJson());
          expect(loaded.activity, activity);
          expect(loaded.hasMeasurement, measured);
          expect(loaded.value.displayText, measured ? '42' : '0');
          expect(loaded.meter.unit, 'mm');
          expect(loaded.currentPhotos.map((photo) => photo.id), [
            photos[1].id,
            photos[2].id,
          ]);
          expect(loaded.photoHistory, isEmpty);
          expect(await readings.loadRevisions(loaded.id), isEmpty);
          expect(
            await integrity.readingManifestHash(loaded),
            loaded.manifestSha256,
          );
          expect(
            await integrity.readingManifestHash(
              loaded.copyWith(hasMeasurement: !measured),
            ),
            isNot(loaded.manifestSha256),
          );
          final changedActivity = CareActivity
              .presets[(activity.index + 1) % CareActivity.presets.length];
          expect(
            await integrity.readingManifestHash(
              loaded.copyWith(activity: changedActivity),
            ),
            isNot(loaded.manifestSha256),
          );
          expected.add(loaded);
        }
      }
      final backup = await EncryptedBackupService(
        meters: meters,
        readings: readings,
        exports: exports,
        reminders: reminders,
        temporaryDirectoryProvider: () async => temp,
        documentsDirectoryProvider: () async => temp,
        kdfIterations: 1000,
      ).create('fixture-only');
      final target = AppDatabase.memory();
      addTearDown(target.close);
      final restoredReadings = DriftMeterReadingRepository(target);
      final result = await EncryptedBackupService(
        meters: DriftMeterRepository(target),
        readings: restoredReadings,
        exports: DriftEvidenceExportRepository(target),
        reminders: reminders,
        temporaryDirectoryProvider: () async => temp,
        documentsDirectoryProvider: () async =>
            Directory('${temp.path}/restored')..createSync(),
        kdfIterations: 1000,
      ).restore(backup.path, 'fixture-only');
      expect(result.readings, expected.length);
      for (final reading in expected) {
        final restored = (await restoredReadings.findById(reading.id))!;
        expect(restored.activity, reading.activity);
        expect(restored.hasMeasurement, reading.hasMeasurement);
        expect(restored.value, reading.value);
        expect(restored.summary, reading.summary);
        expect(
          restored.currentPhotos.map((p) => p.id),
          reading.currentPhotos.map((p) => p.id),
        );
        expect(
          restored.photoHistory.map((p) => p.id),
          reading.photoHistory.map((p) => p.id),
        );
        expect(
          await integrity.readingManifestHash(restored),
          reading.manifestSha256,
        );
        expect(await restoredReadings.loadRevisions(reading.id), isEmpty);
        for (final photo in restored.allPhotoVersions) {
          expect(
            await integrity.sha256Bytes(await File(photo.path).readAsBytes()),
            photo.sha256,
          );
        }
      }
    },
  );
}
