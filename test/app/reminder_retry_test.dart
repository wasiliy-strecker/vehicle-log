import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/app/app_router.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.appfactory.vehicle_log/reminders');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  testWidgets(
    'failed save keeps one record and unchanged reminder can be retried',
    (tester) async {
      var fail = true;
      var scheduleCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'areNotificationsEnabled':
            return true;
          case 'canScheduleExactAlarms':
            return true;
          case 'getNotificationAvailability':
            return 'available';
          case 'getDoNotDisturbStatus':
            return false;
          case 'schedule':
            scheduleCalls++;
            return fail ? 'failed' : 'scheduled';
          case 'getStatuses':
            return [
              for (final id in (call.arguments as Map)['meterIds'] as List)
                {
                  'meterId': id,
                  'planningState': fail ? 'failed' : 'scheduled',
                  'nextTriggerAtMillis': DateTime(
                    2030,
                    1,
                    1,
                    9,
                  ).millisecondsSinceEpoch,
                  'isExact': false,
                },
            ];
          default:
            return null;
        }
      });
      final meters = MemoryMeterRepository()
        ..items['saved'] = Meter(
          id: 'saved',
          label: 'Gespeichert',
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
      final repair = find.text('Erinnerung bearbeiten');
      await tester.ensureVisible(repair);
      await tester.tap(repair);
      await tester.pumpAndSettle();
      final retry = find.text('Erinnerung erneut speichern');
      expect(retry, findsOneWidget);
      final before = scheduleCalls;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(scheduleCalls, before + 1);
      expect(meters.items, hasLength(1));
      expect(
        find.textContaining(
          'Daten gespeichert. Die Erinnerung konnte nicht bestätigt',
        ),
        findsOneWidget,
      );
      final router = ProviderScope.containerOf(
        tester.element(find.byType(MeterReadingLogApp)),
      ).read(appRouterProvider);
      router.pushNamed('meterEdit', pathParameters: {'id': 'saved'});
      await tester.pumpAndSettle();
      fail = false;
      await tester.tap(find.text('Erinnerung erneut speichern'));
      await tester.pumpAndSettle();
      expect(meters.items, hasLength(1));
      expect(meters.items['saved']!.label, 'Gespeichert');
      expect(find.text('Nächste Erinnerung'), findsOneWidget);
      expect(find.text('Erinnerung nicht geplant'), findsNothing);
      expect(find.text('Änderungen am Fahrzeug gespeichert.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
