import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.appfactory.vehicle_log/reminders');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final scenario in [
    'scheduleFailure',
    'missingExact',
    'overdue',
    'unconfirmed',
  ]) {
    testWidgets('Android planning state reaches dashboard: $scenario', (
      tester,
    ) async {
      final punctual = scenario == 'missingExact';
      final overdue = DateTime(2026, 9, 15, 9);
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'areNotificationsEnabled':
            return true;
          case 'getNotificationAvailability':
            return 'available';
          case 'canScheduleExactAlarms':
            return !punctual;
          case 'schedule':
            if (scenario == 'scheduleFailure') {
              throw PlatformException(code: 'schedule_failed');
            }
            return 'scheduled';
          case 'getStatuses':
            return [
              {
                'meterId': 'saved',
                'isNotificationActive': false,
                'planningState': scenario == 'unconfirmed'
                    ? 'none'
                    : 'scheduled',
                'nextTriggerAtMillis': scenario == 'unconfirmed'
                    ? null
                    : overdue.millisecondsSinceEpoch,
                'isExact': !punctual,
              },
            ];
          default:
            return null;
        }
      });
      final meters = MemoryMeterRepository()
        ..items['saved'] = Meter(
          id: 'saved',
          label: 'Testeintrag',
          type: MeterType.values.first,
          unit: MeterType.values.first.defaultUnit,
          meterNumber: '',
          location: '',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          reminder: ReadingReminderSchedule(
            interval: ReminderInterval.daily,
            day: 1,
            hour: 9,
            minute: 0,
            deliveryMode: punctual
                ? ReminderDeliveryMode.punctualWithSound
                : ReminderDeliveryMode.normal,
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meterRepositoryProvider.overrideWithValue(meters),
            meterReadingRepositoryProvider.overrideWithValue(
              MemoryReadingRepository(),
            ),
            evidenceExportRepositoryProvider.overrideWithValue(
              MemoryEvidenceExportRepository(),
            ),
            meterReminderRepositoryProvider.overrideWithValue(
              LocalNotificationReminderRepository.instance,
            ),
          ],
          child: const MeterReadingLogApp(),
        ),
      );
      await tester.pumpAndSettle();
      final title = switch (scenario) {
        'missingExact' => 'Pünktlichkeit nicht erlaubt',
        'overdue' => 'Erinnerung steht noch aus',
        _ => 'Erinnerung nicht geplant',
      };
      expect(find.text(title), findsOneWidget);
      expect(find.text('Nächste Erinnerung'), findsNothing);
      if (scenario == 'overdue') {
        expect(find.textContaining('15.09.2026, 09:00'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
