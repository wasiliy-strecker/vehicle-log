import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/core/reminders/reminder_save_feedback.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.appfactory.vehicle_log/reminders');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final repository = LocalNotificationReminderRepository.instance;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  for (final response in ['failed', 'exception', 'missing']) {
    test(
      'scheduling $response remains visible even if native status query fails',
      () async {
        final meter = _meter('failure-$response');
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'areNotificationsEnabled') return true;
          if (call.method == 'schedule' && response != 'exception') {
            return response == 'missing' ? null : response;
          }
          throw PlatformException(code: 'synthetic');
        });
        expect(
          await repository.schedule(meter),
          ReminderOperationResult.failed,
        );
        final status = (await repository.loadStatuses([meter.id]))[meter.id]!;
        expect(status.planningState, ReminderPlanningState.failed);
        expect(status.nextTriggerAt, isNull);
        expect(
          await reminderSaveWarning(repository, meter),
          contains('Daten gespeichert'),
        );
      },
    );
  }
  test(
    'successful retry clears old failure and uses Android timestamp',
    () async {
      final meter = _meter('retry');
      var fail = true;
      final trigger = DateTime.utc(2030, 2, 3, 9);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'areNotificationsEnabled' => true,
          'getNotificationAvailability' => 'available',
          'schedule' => fail ? 'failed' : 'scheduled',
          'getStatuses' => [
            {
              'meterId': meter.id,
              'planningState': 'scheduled',
              'nextTriggerAtMillis': trigger.millisecondsSinceEpoch,
              'isExact': false,
            },
          ],
          _ => null,
        },
      );
      expect(await repository.schedule(meter), ReminderOperationResult.failed);
      expect(
        (await repository.loadStatuses([meter.id]))[meter.id]!.nextTriggerAt,
        isNull,
      );
      fail = false;
      expect(
        await repository.schedule(meter),
        ReminderOperationResult.scheduled,
      );
      final status = (await repository.loadStatuses([meter.id]))[meter.id]!;
      expect(status.planningState, ReminderPlanningState.scheduled);
      expect(status.nextTriggerAt, trigger);
      expect(await reminderSaveWarning(repository, meter), isNull);
    },
  );
  test(
    'blocked permission does not discard the saved native schedule',
    () async {
      var scheduled = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'schedule') {
          scheduled = true;
          return 'scheduled';
        }
        if (call.method == 'getNotificationAvailability') return 'appBlocked';
        return false;
      });
      expect(
        await repository.schedule(_meter('blocked')),
        ReminderOperationResult.blocked,
      );
      expect(scheduled, isTrue);
    },
  );
  test(
    'disable cancels without permission and cancellation failure can be retried',
    () async {
      final meter = _meter('cancel').copyWith(clearReminder: true);
      var fail = true;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'cancel') return fail ? 'failed' : 'cancelled';
        if (call.method == 'getStatuses') {
          return [
            {'meterId': meter.id, 'planningState': 'none'},
          ];
        }
        throw StateError('Unexpected call ${call.method}');
      });
      expect(await repository.schedule(meter), ReminderOperationResult.failed);
      expect(calls, ['cancel']);
      expect(
        (await repository.loadStatuses([meter.id]))[meter.id]!.planningState,
        ReminderPlanningState.cancelFailed,
      );
      expect(
        await reminderSaveWarning(repository, meter),
        contains('nicht ausgeschaltet'),
      );
      fail = false;
      expect(
        await repository.cancel(meter.id),
        ReminderOperationResult.cancelled,
      );
      expect(
        (await repository.loadStatuses([meter.id]))[meter.id]!.planningState,
        ReminderPlanningState.none,
      );
      expect(await reminderSaveWarning(repository, meter), isNull);
    },
  );
}

Meter _meter(String id) => Meter(
  id: id,
  label: 'Test',
  type: MeterType.values.first,
  unit: MeterType.values.first.defaultUnit,
  meterNumber: '',
  location: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  reminder: const ReadingReminderSchedule(
    interval: ReminderInterval.daily,
    day: 1,
    hour: 9,
    minute: 0,
  ),
);
