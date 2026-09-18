import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/features/backup/application/binary_backup_codec.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/meters/application/reading_revision_photos.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v5 restores and repairs every current and historical photo with revision IDs',
    () async {
      final temp = await Directory.systemTemp.createTemp('multiple_backup_');
      addTearDown(() => temp.delete(recursive: true));
      const integrity = IntegrityService();
      final photos = <ReadingPhotoVersion>[];
      for (var index = 0; index < 4; index++) {
        final file = File('${temp.path}/$index.jpg')
          ..writeAsBytesSync([index, 10, 20]);
        photos.add(
          ReadingPhotoVersion(
            id: 'p$index',
            path: file.path,
            sha256: await integrity.sha256Bytes(await file.readAsBytes()),
            source: ReadingSource.gallery,
            addedAt: DateTime.utc(2026, 9, 16),
            ocrRawText: '',
            ocrCandidate: '',
          ),
        );
      }
      final meters = MemoryMeterRepository()..items['book'] = sampleBook();
      final readings = MemoryReadingRepository();
      final exports = MemoryEvidenceExportRepository();
      var reading = sampleReading(path: photos[0].path, hash: photos[0].sha256)
          .copyWith(
            photos: [photos[2], photos[0], photos[1]],
            photoHistory: [photos[3]],
          );
      reading = reading.copyWith(
        manifestSha256: await integrity.readingManifestHash(reading),
      );
      await readings.save(reading);
      final revision = ReadingRevision(
        id: 'revision',
        readingId: reading.id,
        changedAt: reading.updatedAt,
        reason: '',
        changes: {},
        photoChange: const ReadingPhotoChange(
          beforeIds: ['p0', 'p3'],
          afterIds: ['p2', 'p0', 'p1'],
        ),
      );
      await readings.saveRevision(revision);
      EncryptedBackupService backupService(MemoryReadingRepository target) =>
          EncryptedBackupService(
            meters: meters,
            readings: target,
            exports: exports,
            reminders: NoopMeterReminderRepository(),
            temporaryDirectoryProvider: () async => temp,
            documentsDirectoryProvider: () async => temp,
            kdfIterations: 1000,
          );
      final backup = await backupService(readings).create('fixture-only');
      final reader = await BinaryBackupReader.open(backup.path, 'fixture-only');
      expect(reader.version, 6);
      reader.close();
      final target = MemoryReadingRepository();
      await backupService(target).restore(backup.path, 'fixture-only');
      var restored = target.items.values.single;
      expect(restored.currentPhotos.map((p) => p.id), ['p2', 'p0', 'p1']);
      expect(restored.photoHistory.single.id, 'p3');
      expect(
        await integrity.readingManifestHash(restored),
        reading.manifestSha256,
      );
      final restoredRevision = (await target.loadRevisions(reading.id)).single;
      expect(restoredRevision.toJson(), revision.toJson());
      expect(
        photosForRevision(
          reading: restored,
          revision: restoredRevision,
        )!.beforeList.map((p) => p.id),
        ['p0', 'p3'],
      );
      await File(restored.currentPhotos[1].path).delete();
      await File(restored.photoHistory.single.path).writeAsBytes([99]);
      restored = restored.copyWith(
        updatedAt: DateTime.utc(2027),
        note: 'Neuere Notiz',
      );
      await target.save(restored);
      final repaired = await backupService(
        target,
      ).restore(backup.path, 'fixture-only');
      expect(repaired.readings, 0);
      expect(repaired.repairedPhotos, 2);
      final latest = target.items.values.single;
      expect(latest.note, 'Neuere Notiz');
      expect(await File(latest.currentPhotos[1].path).readAsBytes(), [
        0,
        10,
        20,
      ]);
      expect(await File(latest.photoHistory.single.path).readAsBytes(), [
        3,
        10,
        20,
      ]);
    },
  );

  test(
    'original plant v3 backup is rejected without writing vehicle data',
    () async {
      final temp = await Directory.systemTemp.createTemp('legacy_backup_');
      addTearDown(() => temp.delete(recursive: true));
      final readings = MemoryReadingRepository();
      final service = EncryptedBackupService(
        meters: MemoryMeterRepository(),
        readings: readings,
        exports: MemoryEvidenceExportRepository(),
        reminders: NoopMeterReminderRepository(),
        documentsDirectoryProvider: () async => temp,
        temporaryDirectoryProvider: () async => temp,
        kdfIterations: 1000,
      );
      const path = 'test/fixtures/legacy_single_photo_v3.pfbackup';
      await expectLater(
        service.inspect(path, 'fixture-only'),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        service.restore(path, 'fixture-only'),
        throwsA(isA<BackupException>()),
      );
      expect(readings.items, isEmpty);
    },
  );
}
