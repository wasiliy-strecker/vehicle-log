import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/app/app_router.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';

import '../support/fakes.dart';

void main() {
  for (final editing in [true, false]) {
    testWidgets(
      'notification preserves an open ${editing ? 'edit' : 'new'} form',
      (tester) async {
        final meters = MemoryMeterRepository()..items['saved'] = _meter();
        final reminders = _Reminders();
        await tester.pumpWidget(_app(meters, reminders));
        await tester.pumpAndSettle();
        final router = _router(tester);
        if (editing) {
          router.pushNamed('meterEdit', pathParameters: {'id': 'saved'});
        } else {
          router.pushNamed('meterNew');
        }
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Offene Eingabe',
        );
        await tester.pumpAndSettle();
        reminders.opened.add('saved');
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/meter/saved');
        // A second tap must not stack the same notification target twice.
        reminders.opened.add('saved');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(
          router.state.uri.path,
          editing ? '/meter/saved/edit' : '/meter/new',
        );
        expect(find.text('Offene Eingabe'), findsOneWidget);
        expect(meters.items, hasLength(1));
        expect(meters.items['saved']!.label, 'Gespeicherter Eintrag');
        expect(tester.takeException(), isNull);
        await _dispose(tester, reminders);
      },
    );
  }

  for (final mode in ReminderDeliveryMode.values) {
    for (final blocked in [
      ReminderAvailability.appBlocked,
      ReminderAvailability.channelBlocked,
    ]) {
      testWidgets(
        'dashboard exposes $blocked for $mode and opens the matching settings',
        (tester) async {
          final meters = MemoryMeterRepository()
            ..items['saved'] = _meter(mode: mode);
          final reminders = _Reminders()..deliveryAvailability[mode] = blocked;
          await tester.pumpWidget(_app(meters, reminders));
          await tester.pumpAndSettle();
          expect(find.text('Erinnerung blockiert'), findsOneWidget);
          expect(find.text('Nächste Erinnerung'), findsNothing);
          final settings = find.text('Einstellungen öffnen');
          await tester.ensureVisible(settings);
          await tester.tap(settings);
          await tester.pumpAndSettle();
          expect(reminders.notificationSettingsOpened, [
            blocked == ReminderAvailability.appBlocked ? null : mode,
          ]);
          expect(_router(tester).state.uri.path, '/');
          reminders.deliveryAvailability[mode] = ReminderAvailability.available;
          reminders.refreshStatuses();
          await tester.pumpAndSettle();
          expect(find.text('Erinnerung blockiert'), findsNothing);
          expect(find.text('Nächste Erinnerung'), findsOneWidget);
          await _dispose(tester, reminders);
        },
      );
    }
  }

  testWidgets('dashboard checks each delivery mode separately', (tester) async {
    final meters = MemoryMeterRepository()
      ..items['saved'] = _meter()
      ..items['punctual'] = _meter(
        id: 'punctual',
        mode: ReminderDeliveryMode.punctualWithSound,
      );
    final reminders = _Reminders()
      ..deliveryAvailability[ReminderDeliveryMode.normal] =
          ReminderAvailability.channelBlocked;
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(meters, reminders));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('next-reminder-saved')),
        matching: find.text('Erinnerung blockiert'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('next-reminder-punctual')),
        matching: find.text('Nächste Erinnerung'),
      ),
      findsOneWidget,
    );
    await _dispose(tester, reminders);
  });

  testWidgets(
    'settings failure explains the manual path and keeps dashboard usable',
    (tester) async {
      final meters = MemoryMeterRepository()..items['saved'] = _meter();
      final reminders = _Reminders()
        ..deliveryAvailability[ReminderDeliveryMode.normal] =
            ReminderAvailability.appBlocked
        ..canOpenSettings = false;
      await tester.pumpWidget(_app(meters, reminders));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Einstellungen öffnen'));
      await tester.tap(find.text('Einstellungen öffnen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('wähle diese App'), findsOneWidget);
      expect(_router(tester).state.uri.path, '/');
      await _dispose(tester, reminders);
    },
  );

  for (final availability in [
    ReminderAvailability.unknown,
    ReminderAvailability.unsupported,
  ]) {
    testWidgets('dashboard does not promise delivery for $availability', (
      tester,
    ) async {
      final meters = MemoryMeterRepository()..items['saved'] = _meter();
      final reminders = _Reminders()
        ..deliveryAvailability[ReminderDeliveryMode.normal] = availability;
      await tester.pumpWidget(_app(meters, reminders));
      await tester.pumpAndSettle();
      expect(find.text('Nächste Erinnerung'), findsNothing);
      expect(find.text('Erinnerung blockiert'), findsNothing);
      expect(
        find.text(
          availability == ReminderAvailability.unknown
              ? 'Planungsstatus unbekannt'
              : 'Erinnerungen nicht unterstützt',
        ),
        findsOneWidget,
      );
      await _dispose(tester, reminders);
    });
  }
}

class _Reminders extends NoopMeterReminderRepository {
  final opened = StreamController<String>.broadcast();
  final changes = StreamController<int>.broadcast();
  final deliveryAvailability = <ReminderDeliveryMode, ReminderAvailability>{};
  bool canOpenSettings = true;
  int revision = 0;

  @override
  Stream<String> get notificationOpened => opened.stream;
  @override
  Stream<int> get statusChanges => changes.stream;
  @override
  void refreshStatuses() => changes.add(++revision);
  @override
  Future<ReminderAvailability> availability(ReminderDeliveryMode mode) async =>
      deliveryAvailability[mode] ?? ReminderAvailability.available;
  @override
  Future<bool> openNotificationSettings({ReminderDeliveryMode? mode}) async {
    notificationSettingsOpened.add(mode);
    return canOpenSettings;
  }
}

Meter _meter({
  String id = 'saved',
  ReminderDeliveryMode mode = ReminderDeliveryMode.normal,
}) => Meter(
  id: id,
  label: 'Gespeicherter Eintrag',
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
    deliveryMode: mode,
  ),
);

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

GoRouter _router(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MeterReadingLogApp)),
).read(appRouterProvider);

Future<void> _dispose(WidgetTester tester, _Reminders reminders) async {
  await tester.pumpWidget(const SizedBox());
  await reminders.opened.close();
  await reminders.changes.close();
}
