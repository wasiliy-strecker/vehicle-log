import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'manual entries retain values and manifests through SQLite and corrections',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final meters = DriftMeterRepository(db);
      final readings = DriftMeterReadingRepository(db);
      final reminders = NoopMeterReminderRepository();
      final book = sampleBook().copyWith(unit: 'Kapitel');
      await meters.save(book);
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: DriftEvidenceExportRepository(db),
        photos: _NoPhotoAccess(),
        evidencePhotos: _NoAssets(),
        reminders: reminders,
      );
      final time = DateTime.utc(2026, 9, 15, 5, 0, 0, 123, 456);
      final created = await service.createManual(
        meter: book,
        value: ReadingValue.tryParseWhole('0007')!,
        capturedAt: time,
        note: '  Kapitel fertig  ',
      );
      final loaded = (await readings.findById(created.id))!;
      expect(loaded.toJson(), created.toJson());
      expect(loaded.value.displayText, '0007');
      expect(loaded.meter.unit, 'Kapitel');
      expect(loaded.note, 'Kapitel fertig');
      expect(loaded.source, ReadingSource.manual);
      expect(loaded.hasPhoto, isFalse);
      expect(loaded.currentPhotoVersion, isNull);
      expect(loaded.allPhotoPaths, isEmpty);
      expect(loaded.allPhotoVersions, isEmpty);
      expect(loaded.photoSha256, isEmpty);
      expect(loaded.photoAddedAt, isNull);
      expect(loaded.ocrCandidate, isEmpty);
      expect(loaded.ocrConfidence, isNull);
      expect(loaded.wasManuallyCorrected, isFalse);
      expect(
        await const IntegrityService().readingManifestHash(loaded),
        loaded.manifestSha256,
      );
      expect(reminders.acknowledgedMeterIds, [book.id]);
      final corrected = await service.update(
        existing: loaded,
        value: ReadingValue.tryParseWhole('8')!,
        capturedAt: loaded.capturedAt,
        note: 'Korrigiert',
      );
      final reloaded = (await readings.findById(loaded.id))!;
      expect(reloaded.toJson(), corrected.toJson());
      expect(reloaded.source, ReadingSource.manual);
      expect(
        await const IntegrityService().readingManifestHash(reloaded),
        reloaded.manifestSha256,
      );
      expect(await readings.loadRevisions(loaded.id), isEmpty);
      await service.delete(reloaded);
      expect(await readings.findById(loaded.id), isNull);
      expect(await readings.loadRevisions(loaded.id), isEmpty);
      for (final value in ['1,5', '12-13']) {
        await expectLater(
          service.createManual(
            meter: book,
            value: ReadingValue.tryParse(value)!,
            capturedAt: time,
            note: '',
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('adding and replacing photos keeps only the current version', () async {
    final readings = MemoryReadingRepository();
    final service = MeterReadingService(
      meters: MemoryMeterRepository(),
      readings: readings,
      exports: MemoryEvidenceExportRepository(),
      photos: _NoPhotoAccess(),
      reminders: NoopMeterReminderRepository(),
    );
    final manual = sampleReading(source: ReadingSource.manual);
    final updated = await service.update(
      existing: manual,
      value: manual.value,
      capturedAt: manual.capturedAt,
      note: '',
      replacementPhoto: StoredMeterPhoto(
        path: '/added.jpg',
        sha256: 'b' * 64,
        source: ReadingSource.gallery,
        capturedAt: manual.capturedAt,
      ),
    );
    expect(await readings.loadRevisions(manual.id), isEmpty);
    expect(updated.hasPhoto, isTrue);
    expect(updated.source, ReadingSource.gallery);
    expect(updated.photoHistory, isEmpty);
    expect(updated.allPhotoPaths, {'/added.jpg'});
    final replaced = await service.update(
      existing: updated,
      value: updated.value,
      capturedAt: updated.capturedAt,
      note: '',
      replacementPhoto: StoredMeterPhoto(
        path: '/next.jpg',
        sha256: 'c' * 64,
        source: ReadingSource.camera,
        capturedAt: manual.capturedAt,
      ),
    );
    expect(replaced.photoHistory, isEmpty);
    expect(replaced.allPhotoPaths, {'/next.jpg'});
  });

  for (final mixed in [false, true]) {
    test(
      'encrypted backup restores manual entries and PDFs, mixed=$mixed',
      () async {
        final temp = await Directory.systemTemp.createTemp('manual_backup_');
        addTearDown(() => temp.delete(recursive: true));
        final targetDb = AppDatabase.memory();
        addTearDown(targetDb.close);
        final meters = MemoryMeterRepository();
        final readings = MemoryReadingRepository();
        final exports = MemoryEvidenceExportRepository();
        final book = sampleBook();
        await meters.save(book);
        final service = MeterReadingService(
          meters: meters,
          readings: readings,
          exports: exports,
          photos: _NoPhotoAccess(),
          evidencePhotos: _NoAssets(),
          reminders: NoopMeterReminderRepository(),
        );
        final manual = await service.createManual(
          meter: book,
          value: ReadingValue.tryParseWhole('0')!,
          capturedAt: DateTime.utc(2026, 9, 1),
          note: 'Manuelle Notiz',
        );
        final pdf = File('${temp.path}/manual.pdf');
        await pdf.writeAsString('%PDF synthetic document');
        await exports.save(
          EvidenceExportRecord(
            id: 'single',
            meterId: book.id,
            kind: EvidenceExportKind.singleReading,
            readingIds: [manual.id],
            createdAt: DateTime.utc(2026),
            fileName: 'manual.pdf',
            filePath: pdf.path,
            pdfSha256: await const IntegrityService().sha256Bytes(
              await pdf.readAsBytes(),
            ),
            manifestSha256: manual.manifestSha256,
          ),
        );
        if (mixed) {
          final photo = File('${temp.path}/photo.jpg')
            ..writeAsBytesSync([1, 2, 3]);
          await readings.save(
            sampleReading(
              path: photo.path,
              hash: await const IntegrityService().sha256Bytes(
                await photo.readAsBytes(),
              ),
            ),
          );
        }
        final backup = await EncryptedBackupService(
          meters: meters,
          readings: readings,
          exports: exports,
          reminders: NoopMeterReminderRepository(),
          kdfIterations: 1000,
          temporaryDirectoryProvider: () async => temp,
          documentsDirectoryProvider: () async => temp,
        ).create('123456');
        final restoredReadings = DriftMeterReadingRepository(targetDb);
        final restoredExports = DriftEvidenceExportRepository(targetDb);
        final target = EncryptedBackupService(
          meters: DriftMeterRepository(targetDb),
          readings: restoredReadings,
          exports: restoredExports,
          reminders: NoopMeterReminderRepository(),
          kdfIterations: 1000,
          temporaryDirectoryProvider: () async => temp,
          documentsDirectoryProvider: () async =>
              Directory('${temp.path}/target'),
        );
        final result = await target.restore(backup.path, '123456');
        expect(result.readings, mixed ? 2 : 1);
        final restored = (await restoredReadings.findById(manual.id))!;
        expect(restored.toJson(), manual.toJson());
        expect(
          await const IntegrityService().readingManifestHash(restored),
          manual.manifestSha256,
        );
        final restoredPdf = (await restoredExports.loadAll()).single;
        expect(
          await File(restoredPdf.filePath).readAsString(),
          '%PDF synthetic document',
        );
        if (mixed) {
          expect(
            await File(
              (await restoredReadings.findById('reading'))!.photoPath,
            ).readAsBytes(),
            [1, 2, 3],
          );
        } else {
          expect(
            await Directory('${temp.path}/target/meter_photos').exists(),
            isFalse,
          );
        }
        expect((await target.restore(backup.path, '123456')).readings, 0);
        await service.delete(manual);
        expect(await pdf.exists(), isFalse);
        expect(await exports.loadAll(), isEmpty);
      },
    );
  }
}

class _NoPhotoAccess extends UnsupportedMeterPhotoCaptureRepository {
  @override
  Future<void> delete(String path) async =>
      fail('Unexpected photo deletion: $path');
}

class _NoAssets extends NoopEvidencePhotoAssetRepository {
  @override
  Future<String?> prepare({
    required String path,
    required String sha256,
  }) async => fail('Unexpected photo preparation');
  @override
  Future<void> delete(String sha256) async =>
      fail('Unexpected photo cache deletion');
}
