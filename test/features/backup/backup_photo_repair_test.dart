import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final newer in [false, true]) {
    test(
      'restore repairs photos without changing local data, newer=$newer',
      () async {
        final temp = await Directory.systemTemp.createTemp('backup_repair_');
        addTearDown(() => temp.delete(recursive: true));
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final meters = DriftMeterRepository(db);
        final readings = DriftMeterReadingRepository(db);
        final exports = DriftEvidenceExportRepository(db);
        final reminders = NoopMeterReminderRepository();
        const integrity = IntegrityService();
        final photo = File('${temp.path}/current.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        final previous = File('${temp.path}/previous.jpg')
          ..writeAsBytesSync([4, 5, 6]);
        final book = sampleBook();
        await meters.save(book);
        var reading =
            sampleReading(
              path: photo.path,
              hash: await integrity.sha256Bytes(await photo.readAsBytes()),
              value: '12,5', // Existing decimals remain fully restorable.
            ).copyWith(
              photoHistory: [
                ReadingPhotoVersion(
                  id: 'previous',
                  path: previous.path,
                  sha256: await integrity.sha256Bytes(
                    await previous.readAsBytes(),
                  ),
                  source: ReadingSource.gallery,
                  addedAt: DateTime.utc(2026, 9, 1),
                  ocrRawText: '10,5',
                  ocrCandidate: '10,5',
                ),
              ],
            );
        reading = reading.copyWith(
          manifestSha256: await integrity.readingManifestHash(reading),
        );
        await readings.save(reading);
        final service = EncryptedBackupService(
          meters: meters,
          readings: readings,
          exports: exports,
          reminders: reminders,
          kdfIterations: 1000,
          temporaryDirectoryProvider: () async => temp,
          documentsDirectoryProvider: () async => temp,
        );
        final backup = await service.create('123456');
        if (newer) {
          reading = reading.copyWith(
            value: ReadingValue.tryParseWhole('90')!,
            note: 'Neuere lokale Notiz',
            updatedAt: DateTime.utc(2026, 9, 15),
          );
          reading = reading.copyWith(
            manifestSha256: await integrity.readingManifestHash(reading),
          );
          await readings.save(reading);
          await readings.saveRevision(
            ReadingRevision(
              id: 'local-revision',
              readingId: reading.id,
              changedAt: reading.updatedAt,
              reason: '',
              changes: const {
                'Notiz': ReadingChange(
                  before: '',
                  after: 'Neuere lokale Notiz',
                ),
              },
            ),
          );
        }
        final revisions = (await readings.loadRevisions(
          reading.id,
        )).map((r) => r.toJson()).toList();
        await photo.delete();
        await previous.writeAsBytes([0]); // Existing file with wrong bytes.
        final result = await service.restore(backup.path, '123456');
        expect(result.readings, 0);
        expect(result.repairedPhotos, 2);
        final restored = (await readings.findById(reading.id))!;
        expect(restored.photoPath, isNot(reading.photoPath));
        expect(
          restored
              .copyWith(
                photoPath: reading.photoPath,
                photoHistory: reading.photoHistory,
              )
              .toJson(),
          reading.toJson(),
        );
        expect(await File(restored.photoPath).readAsBytes(), [1, 2, 3]);
        expect(await File(restored.photoHistory.single.path).readAsBytes(), [
          4,
          5,
          6,
        ]);
        expect(
          await integrity.readingManifestHash(restored),
          restored.manifestSha256,
        );
        expect(
          (await readings.loadRevisions(
            reading.id,
          )).map((r) => r.toJson()).toList(),
          revisions,
        );
        expect(reminders.cancelledMeterIds, contains(book.id));
        final repeated = await service.restore(backup.path, '123456');
        expect(repeated.repairedPhotos, 0);
        expect(
          (await readings.findById(reading.id))!.toJson(),
          restored.toJson(),
        );

        // A newer replacement that is not in this backup must never be replaced
        // by the old photo merely because it belongs to the same reading.
        final unmatched = restored.copyWith(
          photoSha256: 'f' * 64,
          photoPath: '${temp.path}/missing-new.jpg',
          updatedAt: DateTime.utc(2026, 9, 16),
        );
        await readings.save(unmatched);
        expect(
          (await service.restore(backup.path, '123456')).repairedPhotos,
          0,
        );
        expect(
          (await readings.findById(reading.id))!.toJson(),
          unmatched.toJson(),
        );
      },
    );
  }
}
