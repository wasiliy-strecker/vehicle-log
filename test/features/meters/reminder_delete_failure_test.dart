import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import '../../support/fakes.dart';

void main() {
  test(
    'failed cancellation preserves the record and deletion can be retried',
    () async {
      final meter = Meter(
        id: 'saved',
        label: 'Test',
        type: MeterType.values.first,
        unit: MeterType.values.first.defaultUnit,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final meters = MemoryMeterRepository()..items[meter.id] = meter;
      final reminders = _FailingCancellation();
      final service = MeterService(
        meters: meters,
        readings: MemoryReadingRepository(),
        exports: MemoryEvidenceExportRepository(),
        photos: const UnsupportedMeterPhotoCaptureRepository(),
        reminders: reminders,
      );
      await expectLater(service.delete(meter.id), throwsStateError);
      expect(meters.items[meter.id], meter);
      reminders.fail = false;
      await service.delete(meter.id);
      expect(meters.items, isEmpty);
    },
  );
}

class _FailingCancellation extends NoopMeterReminderRepository {
  bool fail = true;
  @override
  Future<ReminderOperationResult> cancel(String meterId) async =>
      fail ? ReminderOperationResult.failed : super.cancel(meterId);
}
