import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/meters/domain/meter.dart';
import '../../features/meters/domain/meter_reading.dart';

enum ReminderPermissionStatus { granted, denied, unknown, unsupported }

enum DoNotDisturbStatus { enabled, disabled, unknown }

enum ReminderAvailability {
  available,
  appBlocked,
  channelBlocked,
  unknown,
  unsupported;

  bool get isBlocked => this == appBlocked || this == channelBlocked;
}

enum ReminderTestResult {
  posted,
  appBlocked,
  channelBlocked,
  failed,
  unsupported;

  ReminderAvailability get availability => switch (this) {
    posted => ReminderAvailability.available,
    appBlocked => ReminderAvailability.appBlocked,
    channelBlocked => ReminderAvailability.channelBlocked,
    unsupported => ReminderAvailability.unsupported,
    failed => ReminderAvailability.unknown,
  };

  String message(DoNotDisturbStatus quietMode) => switch (this) {
    posted =>
      'Test-Erinnerung wurde an Android übergeben. '
          'Ziehe die Benachrichtigungsleiste herunter. '
          'Die Test-Erinnerung verschwindet nach einer Minute.'
          '${quietMode == DoNotDisturbStatus.enabled ? ' „Nicht stören“ ist aktiv. Ton und Banner können unterdrückt werden.' : ''}',
    appBlocked => 'Benachrichtigungen sind nicht erlaubt.',
    channelBlocked => 'Diese Erinnerungsart ist in Android gesperrt.',
    failed => 'Test-Erinnerung konnte nicht angezeigt werden.',
    unsupported =>
      'Test-Erinnerungen werden auf diesem Gerät nicht unterstützt.',
  };
}

enum ReminderOperationResult {
  scheduled,
  cancelled,
  blocked,
  failed,
  unsupported,
}

enum ReminderPlanningState { unknown, scheduled, none, failed, cancelFailed }

class ReminderStatus {
  const ReminderStatus({
    required this.meterId,
    required this.isNotificationActive,
    this.lastTriggeredAt,
    this.nextTriggerAt,
    this.planningState = ReminderPlanningState.unknown,
    this.isExact,
    this.deliveryFailed = false,
  });

  final String meterId;
  final bool isNotificationActive;
  final DateTime? lastTriggeredAt;
  final DateTime? nextTriggerAt;
  final ReminderPlanningState planningState;
  final bool? isExact;
  final bool deliveryFailed;

  bool get needsRepair =>
      planningState == ReminderPlanningState.failed ||
      planningState == ReminderPlanningState.cancelFailed ||
      planningState == ReminderPlanningState.none;
}

class MeterReminderTestRequest {
  const MeterReminderTestRequest({
    required this.label,
    required this.meterType,
    required this.deliveryMode,
    this.meterId,
    this.latestValue,
    this.latestUnit,
  });

  final String label;
  final MeterType meterType;
  final ReminderDeliveryMode deliveryMode;
  final String? meterId;
  final String? latestValue;
  final String? latestUnit;
}

abstract interface class MeterReminderRepository {
  Stream<int> get statusChanges;

  Stream<String> get notificationOpened;

  Future<void> initialize();

  Future<ReminderPermissionStatus> permissionStatus();

  Future<ReminderPermissionStatus> requestPermission();

  Future<bool> canScheduleExactAlarms();

  Future<bool> requestExactAlarmPermission();

  Future<bool> openExactAlarmSettings();

  Future<DoNotDisturbStatus> doNotDisturbStatus();

  Future<bool> openDoNotDisturbSettings();

  Future<ReminderAvailability> availability(ReminderDeliveryMode mode);

  Future<bool> openNotificationSettings({ReminderDeliveryMode? mode});

  Future<ReminderOperationResult> schedule(
    Meter meter, {
    MeterReading? latestReading,
  });

  Future<ReminderOperationResult> cancel(String meterId);

  Future<void> acknowledge(String meterId);

  Future<Map<String, ReminderStatus>> loadStatuses(Iterable<String> meterIds);

  Future<ReminderTestResult> showReminderTest(MeterReminderTestRequest request);

  Future<String?> consumeInitialMeterId();

  void refreshStatuses();
}

class LocalNotificationReminderRepository implements MeterReminderRepository {
  LocalNotificationReminderRepository._();

  static final instance = LocalNotificationReminderRepository._();
  static const _channel = MethodChannel('com.appfactory.vehicle_log/reminders');

  final _statusChanges = StreamController<int>.broadcast();
  final _notificationOpened = StreamController<String>.broadcast();
  int _statusRevision = 0;
  bool _initialized = false;
  final _operationFailures = <String, ReminderPlanningState>{};

  @override
  Stream<int> get statusChanges => _statusChanges.stream;

  @override
  Stream<String> get notificationOpened => _notificationOpened.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!_supportsNotifications) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'statusChanged') {
        refreshStatuses();
      } else if (call.method == 'notificationOpened') {
        final meterId = call.arguments as String?;
        if (meterId != null && meterId.isNotEmpty) {
          _notificationOpened.add(meterId);
          refreshStatuses();
        }
      }
    });
  }

  @override
  Future<ReminderPermissionStatus> permissionStatus() async {
    await initialize();
    if (!_supportsNotifications) return ReminderPermissionStatus.unsupported;
    try {
      final enabled = await _channel.invokeMethod<bool>(
        'areNotificationsEnabled',
      );
      return switch (enabled) {
        true => ReminderPermissionStatus.granted,
        false => ReminderPermissionStatus.denied,
        null => ReminderPermissionStatus.unknown,
      };
    } on Object {
      return ReminderPermissionStatus.unknown;
    }
  }

  @override
  Future<ReminderPermissionStatus> requestPermission() async {
    await initialize();
    if (!_supportsNotifications) return ReminderPermissionStatus.unsupported;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return switch (granted) {
        true => ReminderPermissionStatus.granted,
        false => ReminderPermissionStatus.denied,
        null => ReminderPermissionStatus.unknown,
      };
    } on Object {
      return ReminderPermissionStatus.unknown;
    }
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    await initialize();
    if (!_supportsNotifications) return false;
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    await initialize();
    if (!_supportsNotifications) return false;
    try {
      return await _channel.invokeMethod<bool>('requestExactAlarmPermission') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> openExactAlarmSettings() async {
    await initialize();
    if (!_supportsNotifications) return false;
    try {
      return await _channel.invokeMethod<bool>('openExactAlarmSettings') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<DoNotDisturbStatus> doNotDisturbStatus() async {
    await initialize();
    if (!_supportsNotifications) return DoNotDisturbStatus.unknown;
    try {
      final enabled = await _channel.invokeMethod<bool>(
        'getDoNotDisturbStatus',
      );
      return switch (enabled) {
        true => DoNotDisturbStatus.enabled,
        false => DoNotDisturbStatus.disabled,
        null => DoNotDisturbStatus.unknown,
      };
    } on Object {
      return DoNotDisturbStatus.unknown;
    }
  }

  @override
  Future<bool> openDoNotDisturbSettings() async {
    await initialize();
    if (!_supportsNotifications) return false;
    try {
      return await _channel.invokeMethod<bool>('openDoNotDisturbSettings') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<ReminderAvailability> availability(ReminderDeliveryMode mode) async {
    await initialize();
    if (!_supportsNotifications) return ReminderAvailability.unsupported;
    try {
      final status = await _channel.invokeMethod<String>(
        'getNotificationAvailability',
        {'deliveryMode': mode.name},
      );
      return switch (status) {
        'available' => ReminderAvailability.available,
        'appBlocked' => ReminderAvailability.appBlocked,
        'channelBlocked' => ReminderAvailability.channelBlocked,
        _ => ReminderAvailability.unknown,
      };
    } on Object {
      return ReminderAvailability.unknown;
    }
  }

  @override
  Future<bool> openNotificationSettings({ReminderDeliveryMode? mode}) async {
    await initialize();
    if (!_supportsNotifications) return false;
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings', {
            if (mode != null) 'deliveryMode': mode.name,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<ReminderOperationResult> schedule(
    Meter meter, {
    MeterReading? latestReading,
  }) async {
    await initialize();
    final schedule = meter.reminder;
    if (schedule == null) return cancel(meter.id);
    if (!_supportsNotifications) return ReminderOperationResult.unsupported;
    var permission = await permissionStatus();
    if (permission == ReminderPermissionStatus.denied) {
      permission = await requestPermission();
    }
    // Keep the saved schedule current even while notifications are blocked.
    // Android checks delivery permission again when the alarm actually fires.
    try {
      final result = await _channel.invokeMethod<String>('schedule', {
        'meterId': meter.id,
        'label': meter.label,
        'meterType': meter.type.wireName,
        'meterTypeLabel': meter.type.label,
        'latestValue': latestReading?.summary,
        'latestUnit': latestReading == null ? null : '',
        'interval': schedule.interval.name,
        if (schedule.startsAt != null)
          'startsAtMillis': schedule.startsAt!.millisecondsSinceEpoch,
        'day': schedule.day,
        'month': schedule.month,
        'hour': schedule.hour,
        'minute': schedule.minute,
        'deliveryMode': schedule.deliveryMode.name,
      });
      if (result != 'scheduled') {
        return _failed(meter.id, ReminderPlanningState.failed);
      }
      _operationFailures.remove(meter.id);
      refreshStatuses();
      final available = await availability(schedule.deliveryMode);
      return permission == ReminderPermissionStatus.denied ||
              available.isBlocked
          ? ReminderOperationResult.blocked
          : ReminderOperationResult.scheduled;
    } on Object {
      return _failed(meter.id, ReminderPlanningState.failed);
    }
  }

  @override
  Future<ReminderOperationResult> cancel(String meterId) async {
    await initialize();
    if (!_supportsNotifications) return ReminderOperationResult.unsupported;
    try {
      final result = await _channel.invokeMethod<String>('cancel', {
        'meterId': meterId,
      });
      if (result != 'cancelled') {
        return _failed(meterId, ReminderPlanningState.cancelFailed);
      }
      _operationFailures.remove(meterId);
      refreshStatuses();
      return ReminderOperationResult.cancelled;
    } on Object {
      return _failed(meterId, ReminderPlanningState.cancelFailed);
    }
  }

  ReminderOperationResult _failed(String meterId, ReminderPlanningState state) {
    _operationFailures[meterId] = state;
    refreshStatuses();
    return ReminderOperationResult.failed;
  }

  @override
  Future<void> acknowledge(String meterId) async {
    await initialize();
    if (!_supportsNotifications) return;
    try {
      await _channel.invokeMethod<void>('acknowledge', {'meterId': meterId});
      refreshStatuses();
    } on Object {
      return;
    }
  }

  @override
  Future<Map<String, ReminderStatus>> loadStatuses(
    Iterable<String> meterIds,
  ) async {
    await initialize();
    final ids = meterIds.toList(growable: false);
    if (!_supportsNotifications || ids.isEmpty) return const {};
    final statuses = <String, ReminderStatus>{};
    try {
      final result = await _channel.invokeListMethod<Object?>('getStatuses', {
        'meterIds': ids,
      });
      for (final raw in result ?? const []) {
        if (raw is! Map) continue;
        final values = Map<Object?, Object?>.from(raw);
        final meterId = values['meterId'] as String?;
        if (meterId == null) continue;
        final lastTriggeredMillis = values['lastTriggeredAtMillis'] as int?;
        final nextTriggerMillis = values['nextTriggerAtMillis'] as int?;
        statuses[meterId] = ReminderStatus(
          meterId: meterId,
          isNotificationActive:
              values['isNotificationActive'] as bool? ?? false,
          planningState: switch (values['planningState']) {
            'scheduled' => ReminderPlanningState.scheduled,
            'none' => ReminderPlanningState.none,
            'failed' => ReminderPlanningState.failed,
            'cancelFailed' => ReminderPlanningState.cancelFailed,
            _ => ReminderPlanningState.unknown,
          },
          nextTriggerAt: nextTriggerMillis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  nextTriggerMillis,
                  isUtc: true,
                ),
          isExact: values['isExact'] as bool?,
          deliveryFailed: values['deliveryFailed'] == true,
          lastTriggeredAt: lastTriggeredMillis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  lastTriggeredMillis,
                  isUtc: true,
                ),
        );
      }
    } on Object {
      // A failed query is unknown. Preserve separately observed operation errors.
    }
    for (final id in ids) {
      final failure = _operationFailures[id];
      if (failure == null) continue;
      final previous = statuses[id];
      statuses[id] = ReminderStatus(
        meterId: id,
        isNotificationActive: previous?.isNotificationActive ?? false,
        lastTriggeredAt: previous?.lastTriggeredAt,
        planningState: failure,
      );
    }
    return statuses;
  }

  @override
  Future<ReminderTestResult> showReminderTest(
    MeterReminderTestRequest request,
  ) async {
    await initialize();
    if (!_supportsNotifications) return ReminderTestResult.unsupported;
    var permission = await permissionStatus();
    if (permission != ReminderPermissionStatus.granted) {
      permission = await requestPermission();
    }
    if (permission != ReminderPermissionStatus.granted) {
      return switch (permission) {
        ReminderPermissionStatus.denied => ReminderTestResult.appBlocked,
        ReminderPermissionStatus.unsupported => ReminderTestResult.unsupported,
        _ => ReminderTestResult.failed,
      };
    }
    try {
      final result = await _channel.invokeMethod<String>('showReminderTest', {
        'meterId': request.meterId,
        'label': request.label,
        'meterType': request.meterType.wireName,
        'meterTypeLabel': request.meterType.label,
        'latestValue': request.latestValue,
        'latestUnit': request.latestUnit,
        'deliveryMode': request.deliveryMode.name,
      });
      return switch (result) {
        'posted' => ReminderTestResult.posted,
        'appBlocked' => ReminderTestResult.appBlocked,
        'channelBlocked' => ReminderTestResult.channelBlocked,
        _ => ReminderTestResult.failed,
      };
    } on Object {
      return ReminderTestResult.failed;
    }
  }

  @override
  Future<String?> consumeInitialMeterId() async {
    await initialize();
    if (!_supportsNotifications) return null;
    try {
      return await _channel.invokeMethod<String>('consumeInitialMeterId');
    } on Object {
      return null;
    }
  }

  @override
  void refreshStatuses() {
    if (!_statusChanges.isClosed) _statusChanges.add(++_statusRevision);
  }

  bool get _supportsNotifications =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

DateTime nextReminderDate(ReadingReminderSchedule schedule, DateTime now) {
  if (schedule.interval == ReminderInterval.hourly) {
    final startsAt = schedule.startsAt;
    if (startsAt == null) {
      throw ArgumentError(
        'Die stündliche Erinnerung benötigt einen Startzeitpunkt.',
      );
    }
    final start = startsAt.toUtc();
    final current = now.toUtc();
    if (start.isAfter(current)) return start.toLocal();
    final elapsedHours =
        current.difference(start).inMicroseconds ~/
        Duration.microsecondsPerHour;
    return start.add(Duration(hours: elapsedHours + 1)).toLocal();
  }

  if (schedule.interval == ReminderInterval.minutely) {
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
  }

  if (schedule.interval == ReminderInterval.daily) {
    var candidate = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.hour,
      schedule.minute,
    );
    if (!candidate.isAfter(now)) {
      candidate = DateTime(
        now.year,
        now.month,
        now.day + 1,
        schedule.hour,
        schedule.minute,
      );
    }
    return candidate;
  }

  if (schedule.interval == ReminderInterval.weekly) {
    final weekday = schedule.day.clamp(DateTime.monday, DateTime.sunday);
    var daysAhead = (weekday - now.weekday) % DateTime.daysPerWeek;
    var candidate = DateTime(
      now.year,
      now.month,
      now.day + daysAhead,
      schedule.hour,
      schedule.minute,
    );
    if (!candidate.isAfter(now)) {
      daysAhead += DateTime.daysPerWeek;
      candidate = DateTime(
        now.year,
        now.month,
        now.day + daysAhead,
        schedule.hour,
        schedule.minute,
      );
    }
    return candidate;
  }

  if (schedule.interval == ReminderInterval.monthly) {
    var year = now.year;
    var month = now.month;
    var candidate = _safeDate(
      year,
      month,
      schedule.day,
      schedule.hour,
      schedule.minute,
    );
    if (!candidate.isAfter(now)) {
      month += 1;
      if (month == 13) {
        month = 1;
        year += 1;
      }
      candidate = _safeDate(
        year,
        month,
        schedule.day,
        schedule.hour,
        schedule.minute,
      );
    }
    return candidate;
  }

  final month = schedule.month ?? now.month;
  var candidate = _safeDate(
    now.year,
    month,
    schedule.day,
    schedule.hour,
    schedule.minute,
  );
  if (!candidate.isAfter(now)) {
    candidate = _safeDate(
      now.year + 1,
      month,
      schedule.day,
      schedule.hour,
      schedule.minute,
    );
  }
  return candidate;
}

DateTime _safeDate(int year, int month, int day, int hour, int minute) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day.clamp(1, lastDay), hour, minute);
}
