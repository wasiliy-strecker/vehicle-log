import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import '../../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final throwing in [false, true]) {
    test(
      'restore keeps data and continues after reminder failure, throwing=$throwing',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'reminder_restore_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final original = MemoryMeterRepository();
        for (final id in ['failure', 'working']) {
          original.items[id] = Meter(
            id: id,
            label: 'Test $id',
            type: MeterType.values.first,
            unit: MeterType.values.first.defaultUnit,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            reminder: const ReadingReminderSchedule(
              interval: ReminderInterval.daily,
              day: 1,
              hour: 9,
              minute: 0,
            ),
          );
        }
        EncryptedBackupService service(
          MemoryMeterRepository meters,
          NoopMeterReminderRepository reminders,
        ) => EncryptedBackupService(
          meters: meters,
          readings: MemoryReadingRepository(),
          exports: MemoryEvidenceExportRepository(),
          reminders: reminders,
          kdfIterations: 1000,
          temporaryDirectoryProvider: () async => directory,
          documentsDirectoryProvider: () async => directory,
        );
        final backup = await service(
          original,
          NoopMeterReminderRepository(),
        ).create('123456');
        final restored = MemoryMeterRepository();
        final reminders = _FailingReminders(throwing);
        final result = await service(
          restored,
          reminders,
        ).restore(backup.path, '123456');
        expect(result.meters, 2);
        expect(result.reminderIssues, 1);
        expect(restored.items.keys, containsAll(['failure', 'working']));
        expect(reminders.scheduledMeters.single.id, 'working');
      },
    );
  }
}

class _FailingReminders extends NoopMeterReminderRepository {
  _FailingReminders(this.throwing);
  final bool throwing;
  @override
  Future<ReminderOperationResult> schedule(
    Meter meter, {
    MeterReading? latestReading,
  }) async {
    if (meter.id == 'failure') {
      if (throwing) throw StateError('Synthetic platform failure');
      return ReminderOperationResult.failed;
    }
    return super.schedule(meter, latestReading: latestReading);
  }
}
