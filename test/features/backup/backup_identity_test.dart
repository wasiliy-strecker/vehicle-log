import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';

import '../../support/fakes.dart';

void main() {
  for (final binary in [true, false]) {
    test('foreign backup is rejected before writes, binary=$binary', () async {
      final directory = await Directory.systemTemp.createTemp(
        'craft_backup_identity_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final meters = MemoryMeterRepository();
      final readings = MemoryReadingRepository();
      final exports = MemoryEvidenceExportRepository();
      final service = EncryptedBackupService(
        meters: meters,
        readings: readings,
        exports: exports,
        reminders: NoopMeterReminderRepository(),
        temporaryDirectoryProvider: () async => directory,
        documentsDirectoryProvider: () async => directory,
      );
      final header = utf8.encode(
        jsonEncode({
          'format': 'meter_reading_log_backup',
          'schemaVersion': binary ? 3 : 2,
        }),
      );
      // Even a renamed LeseLog backup must not become an import for this app.
      final file = File('${directory.path}/renamed.fzbackup');
      if (binary) {
        final archive = Archive()
          ..addFile(ArchiveFile('header.json', header.length, header))
          ..addFile(ArchiveFile('manifest.bin', 1, [0]));
        await file.writeAsBytes(ZipEncoder().encode(archive));
      } else {
        await file.writeAsBytes(header);
      }
      final invalid = throwsA(
        isA<BackupException>().having(
          (error) => error.failure,
          'failure',
          BackupFailure.invalidFormat,
        ),
      );
      await expectLater(service.inspect(file.path, '123456'), invalid);
      await expectLater(service.restore(file.path, '123456'), invalid);
      expect(meters.items, isEmpty);
      expect(readings.items, isEmpty);
      expect(exports.items, isEmpty);
    });
  }
}
