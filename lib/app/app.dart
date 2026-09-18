import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/reminders/local_notification_reminder_repository.dart';
import '../core/reminders/reminder_permission_recovery.dart';
import '../features/meters/domain/meter_reading.dart';
import 'app_router.dart';
import 'app_providers.dart';
import 'app_theme.dart';

class MeterReadingLogApp extends ConsumerStatefulWidget {
  const MeterReadingLogApp({super.key});

  @override
  ConsumerState<MeterReadingLogApp> createState() => _MeterReadingLogAppState();
}

class _MeterReadingLogAppState extends ConsumerState<MeterReadingLogApp>
    with WidgetsBindingObserver {
  late final StreamSubscription<String> _notificationSubscription;
  late final ReminderPermissionRecovery _permissionRecovery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final reminders = ref.read(meterReminderRepositoryProvider);
    _permissionRecovery = ReminderPermissionRecovery(
      reminders: reminders,
      synchronize: () => _synchronizeReminders(reminders),
    );
    _notificationSubscription = reminders.notificationOpened.listen(_openMeter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_permissionRecovery.start());
      unawaited(_openInitialNotification(reminders));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionRecovery.dispose();
    _notificationSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_permissionRecovery.refresh());
    }
  }

  Future<void> _openInitialNotification(
    MeterReminderRepository reminders,
  ) async {
    final meterId = await reminders.consumeInitialMeterId();
    if (mounted && meterId != null) _openMeter(meterId);
  }

  Future<void> _synchronizeReminders(MeterReminderRepository reminders) async {
    if (!mounted) return;
    final meters = await ref.read(meterRepositoryProvider).loadAll();
    for (final meter in meters) {
      if (!mounted) return;
      if (meter.reminder == null) {
        await reminders.cancel(meter.id);
        continue;
      }
      List<MeterReading> readings;
      try {
        readings = await ref
            .read(meterReadingRepositoryProvider)
            .loadForMeter(meter.id);
      } on Object {
        // A missing summary must not prevent this or subsequent schedules.
        readings = const [];
      }
      await reminders.schedule(meter, latestReading: _latestReading(readings));
    }
  }

  MeterReading? _latestReading(List<MeterReading> readings) {
    if (readings.isEmpty) return null;
    return readings.reduce(
      (left, right) => left.capturedAt.isAfter(right.capturedAt) ? left : right,
    );
  }

  void _openMeter(String meterId) {
    final router = ref.read(appRouterProvider);
    if (router.state.name == 'meterDetail' &&
        router.state.pathParameters['id'] == meterId) {
      return;
    }
    // Keep open forms and their unsaved input on the navigation stack.
    unawaited(
      router.pushNamed<void>('meterDetail', pathParameters: {'id': meterId}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      restorationScopeId: 'app',
      title: 'Fahrzeugakte',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(appRouterProvider),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
