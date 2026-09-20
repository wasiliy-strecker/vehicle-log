import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failureTable in ['reading_records', 'evidence_export_records']) {
    for (final repair in [false, true]) {
      test(
        'restore rolls back data and files on $failureTable failure, repair=$repair',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'vehicle_atomic_restore_',
          );
          final targetRoot = await Directory('${root.path}/target').create();
          final db = AppDatabase.memory();
          addTearDown(() async {
            await db.close();
            await root.delete(recursive: true);
          });
          final originalMeter = sampleBook(
            label: 'Local vehicle',
            updatedAt: DateTime.utc(2026, 9, 1),
          );
          final importedMeter = originalMeter.copyWith(
            label: 'Backup vehicle',
            updatedAt: DateTime.utc(2026, 9, 20),
          );
          final sourceFile = File('${root.path}/source.pdf')
            ..writeAsStringSync('%PDF synthetic original');
          final hash = await const IntegrityService().sha256Stream(
            sourceFile.openRead(),
          );
          final document = ReadingDocument(
            id: 'attachment',
            fileName: 'invoice.pdf',
            path: sourceFile.path,
            sha256: hash,
            pageCount: 1,
            sizeBytes: sourceFile.lengthSync(),
            source: DocumentSource.imported,
            addedAt: DateTime.utc(2026),
          );
          final sourceReading = sampleReading(
            book: importedMeter,
            source: ReadingSource.manual,
          ).copyWith(documents: [document]);
          final sourceMeters = MemoryMeterRepository()
            ..items[importedMeter.id] = importedMeter;
          final sourceReadings = MemoryReadingRepository()
            ..items[sourceReading.id] = sourceReading;
          final sourceExports = MemoryEvidenceExportRepository();
          await sourceExports.save(
            EvidenceExportRecord(
              id: 'report',
              meterId: importedMeter.id,
              kind: EvidenceExportKind.meterHistory,
              readingIds: [sourceReading.id],
              createdAt: DateTime.utc(2026),
              fileName: 'report.pdf',
              filePath: sourceFile.path,
              pdfSha256: hash,
              manifestSha256: 'synthetic',
            ),
          );
          final source = EncryptedBackupService(
            meters: sourceMeters,
            readings: sourceReadings,
            exports: sourceExports,
            reminders: NoopMeterReminderRepository(),
            kdfIterations: 1000,
            temporaryDirectoryProvider: () async => root,
            documentsDirectoryProvider: () async => root,
          );
          final backup = await source.create('test-password');
          final meters = DriftMeterRepository(db);
          final readings = DriftMeterReadingRepository(db);
          final exports = DriftEvidenceExportRepository(db);
          await meters.save(originalMeter);
          final existingFile = File('${targetRoot.path}/existing.pdf')
            ..writeAsStringSync('existing bytes must not change');
          final existing = sourceReading.copyWith(
            note: 'Local note',
            updatedAt: repair
                ? DateTime.utc(2026, 9, 30)
                : DateTime.utc(2026, 9, 1),
            documents: [document.withPath(existingFile.path)],
          );
          await readings.save(existing);
          await db.customStatement(
            "CREATE TRIGGER fail_restore BEFORE INSERT ON $failureTable BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
          );
          final reminders = NoopMeterReminderRepository();
          final target = EncryptedBackupService(
            meters: meters,
            readings: readings,
            exports: exports,
            reminders: reminders,
            kdfIterations: 1000,
            temporaryDirectoryProvider: () async => targetRoot,
            documentsDirectoryProvider: () async => targetRoot,
          );
          await expectLater(
            target.restore(backup.path, 'test-password'),
            throwsA(isA<Exception>()),
          );
          expect(
            (await meters.findById(originalMeter.id))!.toJson(),
            originalMeter.toJson(),
          );
          expect(
            (await readings.findById(existing.id))!.toJson(),
            existing.toJson(),
          );
          expect(await exports.loadAll(), isEmpty);
          expect(
            existingFile.readAsStringSync(),
            'existing bytes must not change',
          );
          expect(
            targetRoot
                .listSync(recursive: true)
                .whereType<File>()
                .map((f) => f.path),
            [existingFile.path],
          );
          expect(reminders.scheduledMeters, isEmpty);
        },
      );
    }
  }
}
