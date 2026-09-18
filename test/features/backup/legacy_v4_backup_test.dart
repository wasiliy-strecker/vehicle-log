import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';

import '../../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('original plant v4 backup is rejected without writes', () async {
    const path = 'test/fixtures/legacy_multiple_photos_v4.pfbackup';
    final temp = await Directory.systemTemp.createTemp('legacy_v4_');
    addTearDown(() => temp.delete(recursive: true));
    final readings = MemoryReadingRepository();
    final backup = EncryptedBackupService(
      meters: MemoryMeterRepository(),
      readings: readings,
      exports: MemoryEvidenceExportRepository(),
      reminders: NoopMeterReminderRepository(),
      documentsDirectoryProvider: () async => temp,
      temporaryDirectoryProvider: () async => temp,
    );
    await expectLater(
      backup.inspect(path, 'fixture-only'),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      backup.restore(path, 'fixture-only'),
      throwsA(isA<BackupException>()),
    );
    expect(readings.items, isEmpty);
  });
}
