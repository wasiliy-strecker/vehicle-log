import 'dart:async';

import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export_page.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading_page.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_repositories.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';

class NoopMeterReminderRepository implements MeterReminderRepository {
  NoopMeterReminderRepository({
    this.statuses = const {},
    this.reminderTestResult = ReminderTestResult.posted,
    this.permission = ReminderPermissionStatus.granted,
    this.exactAlarmPermissionGranted = true,
    this.doNotDisturb = DoNotDisturbStatus.disabled,
    this.doNotDisturbSettingsOpenResult = true,
    this.normalAvailability = ReminderAvailability.available,
    this.punctualAvailability = ReminderAvailability.available,
    this.notificationSettingsOpenResult = true,
    String? initialMeterId,
  }) : _initialMeterId = initialMeterId;

  final Map<String, ReminderStatus> statuses;
  final ReminderTestResult reminderTestResult;
  ReminderPermissionStatus permission;
  bool exactAlarmPermissionGranted;
  DoNotDisturbStatus doNotDisturb;
  bool doNotDisturbSettingsOpenResult;
  int doNotDisturbSettingsOpenCount = 0;
  ReminderAvailability normalAvailability;
  ReminderAvailability punctualAvailability;
  bool notificationSettingsOpenResult;
  final List<ReminderDeliveryMode?> notificationSettingsOpened = [];

  @override
  Future<ReminderAvailability> availability(ReminderDeliveryMode mode) async =>
      permission == ReminderPermissionStatus.denied
      ? ReminderAvailability.appBlocked
      : mode == ReminderDeliveryMode.normal
      ? normalAvailability
      : punctualAvailability;

  @override
  Future<bool> openNotificationSettings({ReminderDeliveryMode? mode}) async {
    notificationSettingsOpened.add(mode);
    return notificationSettingsOpenResult;
  }

  String? _initialMeterId;
  final List<String> acknowledgedMeterIds = [];
  final List<String> cancelledMeterIds = [];
  final List<Meter> scheduledMeters = [];
  final List<MeterReading?> scheduledLatestReadings = [];
  final List<MeterReminderTestRequest> reminderTests = [];
  int exactAlarmSettingsOpenCount = 0;
  int exactAlarmPermissionRequestCount = 0;

  @override
  Future<DoNotDisturbStatus> doNotDisturbStatus() async => doNotDisturb;

  @override
  Future<bool> openDoNotDisturbSettings() async {
    doNotDisturbSettingsOpenCount += 1;
    return doNotDisturbSettingsOpenResult;
  }

  @override
  Stream<String> get notificationOpened => const Stream.empty();

  @override
  Stream<int> get statusChanges => const Stream.empty();

  @override
  Future<void> acknowledge(String meterId) async {
    acknowledgedMeterIds.add(meterId);
    final status = statuses[meterId];
    if (status != null) {
      statuses[meterId] = ReminderStatus(
        meterId: meterId,
        isNotificationActive: false,
        lastTriggeredAt: status.lastTriggeredAt,
        nextTriggerAt: status.nextTriggerAt,
        planningState: status.planningState,
        isExact: status.isExact,
        deliveryFailed: status.deliveryFailed,
      );
    }
  }

  @override
  Future<bool> canScheduleExactAlarms() async => exactAlarmPermissionGranted;

  @override
  Future<ReminderOperationResult> cancel(String meterId) async {
    cancelledMeterIds.add(meterId);
    return ReminderOperationResult.cancelled;
  }

  @override
  Future<String?> consumeInitialMeterId() async {
    final meterId = _initialMeterId;
    _initialMeterId = null;
    return meterId;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, ReminderStatus>> loadStatuses(
    Iterable<String> meterIds,
  ) async {
    final result = <String, ReminderStatus>{};
    for (final meterId in meterIds) {
      final status = statuses[meterId];
      final scheduled = scheduledMeters
          .where((meter) => meter.id == meterId)
          .lastOrNull;
      result[meterId] = ReminderStatus(
        meterId: meterId,
        isNotificationActive: status?.isNotificationActive ?? false,
        lastTriggeredAt: status?.lastTriggeredAt,
        nextTriggerAt:
            status?.nextTriggerAt ??
            (scheduled?.reminder == null
                ? null
                : nextReminderDate(scheduled!.reminder!, DateTime.now())),
        planningState:
            status?.planningState != ReminderPlanningState.unknown &&
                status != null
            ? status.planningState
            : scheduled?.reminder == null
            ? ReminderPlanningState.none
            : ReminderPlanningState.scheduled,
        isExact: status?.isExact ?? exactAlarmPermissionGranted,
        deliveryFailed: status?.deliveryFailed ?? false,
      );
    }
    return result;
  }

  @override
  Future<bool> openExactAlarmSettings() async {
    exactAlarmSettingsOpenCount += 1;
    return true;
  }

  @override
  Future<ReminderPermissionStatus> permissionStatus() async => permission;

  @override
  void refreshStatuses() {}

  @override
  Future<bool> requestExactAlarmPermission() async {
    exactAlarmPermissionRequestCount += 1;
    return true;
  }

  @override
  Future<ReminderPermissionStatus> requestPermission() async => permission;

  @override
  Future<ReminderOperationResult> schedule(
    Meter meter, {
    MeterReading? latestReading,
  }) async {
    if (meter.reminder == null) return cancel(meter.id);
    scheduledMeters.add(meter);
    scheduledLatestReadings.add(latestReading);
    refreshStatuses();
    return ReminderOperationResult.scheduled;
  }

  @override
  Future<ReminderTestResult> showReminderTest(
    MeterReminderTestRequest request,
  ) async {
    reminderTests.add(request);
    if (permission == ReminderPermissionStatus.denied) {
      return ReminderTestResult.appBlocked;
    }
    final status = await availability(request.deliveryMode);
    if (status == ReminderAvailability.appBlocked) {
      return ReminderTestResult.appBlocked;
    }
    if (status == ReminderAvailability.channelBlocked) {
      return ReminderTestResult.channelBlocked;
    }
    return reminderTestResult;
  }
}

class MemoryMeterRepository implements MeterRepository {
  final Map<String, Meter> items = {};

  @override
  Future<void> delete(String id) async => items.remove(id);

  @override
  Future<Meter?> findById(String id) async => items[id];

  @override
  Future<List<Meter>> loadAll() async => items.values.toList();

  @override
  Future<void> save(Meter meter) async => items[meter.id] = meter;

  @override
  Stream<List<Meter>> watchAll() => Stream.value(items.values.toList());
}

class MemoryReadingRepository implements MeterReadingRepository {
  final Map<String, MeterReading> items = {};
  final Map<String, List<ReadingRevision>> revisions = {};
  int watchPageForMeterCalls = 0;
  int loadForMeterCalls = 0;
  int? lastPageLimit;
  int? lastPageOffset;
  String? lastPageQuery;

  @override
  Stream<List<String>> watchActivitySuggestions() => watchAll().map((readings) {
    final ordered = [...readings]
      ..sort((a, b) {
        final time = b.updatedAt.compareTo(a.updatedAt);
        return time != 0 ? time : b.id.compareTo(a.id);
      });
    return careActivitySuggestions(
      ordered
          .where((reading) => reading.activity == CareActivity.custom)
          .map((reading) => reading.customActivityLabel!),
    );
  });

  @override
  Stream<List<MeterReading>> watchAll() => Stream.value(items.values.toList());

  @override
  Future<void> delete(String id) async {
    items.remove(id);
    revisions.remove(id);
  }

  @override
  Future<MeterReading?> findById(String id) async => items[id];

  @override
  Future<List<MeterReading>> loadAll() async => items.values.toList();

  @override
  Future<List<MeterReading>> loadForMeter(String meterId) async {
    loadForMeterCalls++;
    return items.values.where((item) => item.meterId == meterId).toList();
  }

  @override
  Future<List<ReadingRevision>> loadRevisions(String readingId) async =>
      revisions[readingId] ?? const [];

  @override
  Future<void> save(MeterReading reading) async => items[reading.id] = reading;

  @override
  Future<void> saveRevision(ReadingRevision revision) async {
    revisions.putIfAbsent(revision.readingId, () => []).add(revision);
  }

  @override
  Future<void> updateWithRevision(
    MeterReading reading,
    ReadingRevision revision,
  ) async {
    await save(reading);
    await saveRevision(revision);
  }

  @override
  Stream<List<MeterReading>> watchForMeter(String meterId) => Stream.value(
    items.values.where((item) => item.meterId == meterId).toList(),
  );

  @override
  Stream<MeterReadingPage> watchPageForMeter(
    String meterId, {
    required int limit,
    int offset = 0,
    String query = '',
  }) {
    watchPageForMeterCalls++;
    lastPageLimit = limit;
    lastPageOffset = offset;
    lastPageQuery = query;
    final all = items.values.where((item) => item.meterId == meterId).toList()
      ..sort(_newestReadingFirst);
    final matching = all
        .where((reading) => meterReadingMatchesQuery(reading, query))
        .toList(growable: false);
    return Stream.value(
      MeterReadingPage(
        offset: offset,
        readings: matching.skip(offset).take(limit).toList(growable: false),
        totalCount: all.length,
        matchingCount: matching.length,
        latestReading: all.isEmpty ? null : all.first,
        olderNeighbor: matching.length > offset + limit
            ? matching[offset + limit]
            : null,
      ),
    );
  }
}

int _newestReadingFirst(MeterReading left, MeterReading right) {
  final captured = right.capturedAt.compareTo(left.capturedAt);
  if (captured != 0) return captured;
  final stored = right.storedAt.compareTo(left.storedAt);
  if (stored != 0) return stored;
  return right.id.compareTo(left.id);
}

class MemoryEvidenceExportRepository implements EvidenceExportRepository {
  final Map<String, EvidenceExportRecord> items = {};

  @override
  Stream<EvidenceExportPage> watchPageForMeter(
    String meterId, {
    required EvidenceExportKind kind,
    required int limit,
    int offset = 0,
  }) {
    final matching =
        items.values
            .where((item) => item.meterId == meterId && item.kind == kind)
            .toList()
          ..sort(compareExportsNewestFirst);
    return Stream.value(
      EvidenceExportPage(
        exports: matching.skip(offset).take(limit).toList(),
        totalCount: matching.length,
        offset: offset,
      ),
    );
  }

  @override
  Future<void> delete(String id) async => items.remove(id);

  @override
  Future<List<EvidenceExportRecord>> loadAll() async => items.values.toList();

  @override
  Future<List<EvidenceExportRecord>> loadForMeter(String meterId) async =>
      items.values.where((item) => item.meterId == meterId).toList();

  @override
  Future<void> save(EvidenceExportRecord record) async =>
      items[record.id] = record;

  @override
  Stream<List<EvidenceExportRecord>> watchForMeter(String meterId) =>
      Stream.value(
        items.values.where((item) => item.meterId == meterId).toList(),
      );
}
