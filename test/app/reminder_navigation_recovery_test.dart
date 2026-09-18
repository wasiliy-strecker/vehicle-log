import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/app/app_router.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_form_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('saving meter edits shows confirmation on the detail screen', (
    tester,
  ) async {
    final meters = MemoryMeterRepository()
      ..items['saved'] = _meter().copyWith(clearReminder: true);
    await tester.pumpWidget(_app(meters, NoopMeterReminderRepository()));
    await tester.pumpAndSettle();
    final router = _router(tester);
    router.pushNamed('meterDetail', pathParameters: {'id': 'saved'});
    await tester.pumpAndSettle();
    router.pushNamed('meterEdit', pathParameters: {'id': 'saved'});
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'Neuer Fahrzeugname',
    );
    await tester.pump();
    await tester.tap(find.text('Änderungen speichern'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/meter/saved');
    expect(meters.items['saved']!.label, 'Neuer Fahrzeugname');
    expect(find.byType(MeterFormScreen), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Änderungen am Fahrzeug gespeichert.'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final permissions in [(true, false), (false, true), (true, true)]) {
    testWidgets(
      'restores edit route after restart and exact alarm change $permissions',
      (tester) async {
        final meters = MemoryMeterRepository()..items['saved'] = _meter();
        final reminders = NoopMeterReminderRepository(
          exactAlarmPermissionGranted: permissions.$1,
        );
        await tester.pumpWidget(_app(meters, reminders));
        await tester.pumpAndSettle();
        final original = _router(tester);
        original.pushNamed('meterDetail', pathParameters: {'id': 'saved'});
        await tester.pumpAndSettle();
        original.pushNamed('meterEdit', pathParameters: {'id': 'saved'});
        await tester.pumpAndSettle();
        expect(find.byType(MeterFormScreen), findsOneWidget);
        reminders.exactAlarmPermissionGranted = permissions.$2;
        await tester.restartAndRestore();
        await tester.pumpAndSettle();
        final restored = _router(tester);
        expect(
          identical(original, restored),
          isFalse,
          reason:
              'The test must create a new router, not retain the old route in memory.',
        );
        expect(restored.state.uri.path, '/meter/saved/edit');
        expect(
          tester.widget<MeterFormScreen>(find.byType(MeterFormScreen)).meterId,
          'saved',
        );
        expect(find.text('Gespeicherter Testeintrag'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Erinnerung jetzt testen'),
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Alarme & Erinnerungen erlauben'),
          permissions.$2 ? findsNothing : findsOneWidget,
        );
        expect(
          meters.items['saved']!.reminder!.deliveryMode,
          ReminderDeliveryMode.punctualWithSound,
        );
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(restored.state.uri.path, '/meter/saved');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('restores new-entry route without creating a record', (
    tester,
  ) async {
    final meters = MemoryMeterRepository();
    await tester.pumpWidget(_app(meters, NoopMeterReminderRepository()));
    await tester.pumpAndSettle();
    _router(tester).pushNamed('meterNew');
    await tester.pumpAndSettle();
    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(_router(tester).state.uri.path, '/meter/new');
    expect(
      tester.widget<MeterFormScreen>(find.byType(MeterFormScreen)).meterId,
      isNull,
    );
    expect(meters.items, isEmpty);
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    expect(_router(tester).state.uri.path, '/');
  });

  testWidgets(
    'returning from settings keeps route and reschedules only saved data',
    (tester) async {
      final meters = MemoryMeterRepository()..items['saved'] = _meter();
      final reminders = NoopMeterReminderRepository(
        permission: ReminderPermissionStatus.denied,
      );
      await tester.pumpWidget(_app(meters, reminders));
      await tester.pumpAndSettle();
      _router(tester).pushNamed('meterEdit', pathParameters: {'id': 'saved'});
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextFormField &&
              w.controller?.text == 'Gespeicherter Testeintrag',
        ),
        'Ungespeicherte Änderung',
      );
      final before = reminders.scheduledMeters.length;
      reminders.permission = ReminderPermissionStatus.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_router(tester).state.uri.path, '/meter/saved/edit');
      expect(find.text('Ungespeicherte Änderung'), findsOneWidget);
      expect(reminders.scheduledMeters, hasLength(before + 1));
      expect(reminders.scheduledMeters.last.label, 'Gespeicherter Testeintrag');
      expect(meters.items['saved']!.label, 'Gespeicherter Testeintrag');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reminders.scheduledMeters, hasLength(before + 1));
    },
  );
}

GoRouter _router(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MeterReadingLogApp)),
).read(appRouterProvider);

Widget _app(
  MemoryMeterRepository meters,
  NoopMeterReminderRepository reminders,
) => ProviderScope(
  overrides: [
    meterRepositoryProvider.overrideWithValue(meters),
    meterReadingRepositoryProvider.overrideWithValue(MemoryReadingRepository()),
    evidenceExportRepositoryProvider.overrideWithValue(
      MemoryEvidenceExportRepository(),
    ),
    meterReminderRepositoryProvider.overrideWithValue(reminders),
  ],
  child: const MeterReadingLogApp(),
);

Meter _meter() => Meter(
  id: 'saved',
  label: 'Gespeicherter Testeintrag',
  type: MeterType.electricity,
  unit: 'km',
  meterNumber: '',
  location: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  reminder: const ReadingReminderSchedule(
    interval: ReminderInterval.daily,
    day: 1,
    hour: 9,
    minute: 0,
    deliveryMode: ReminderDeliveryMode.punctualWithSound,
  ),
);
