import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/core/reminders/reminder_permission_recovery.dart';

import '../../support/fakes.dart';

void main() {
  test(
    'resynchronizes once after regrant, including an intervening unknown query',
    () async {
      final repository = _Events();
      var syncs = 0;
      final recovery = ReminderPermissionRecovery(
        reminders: repository,
        synchronize: () async {
          syncs++;
        },
      );
      addTearDown(recovery.dispose);
      addTearDown(repository.events.close);
      await recovery.start();
      expect(syncs, 1);
      repository.permission = ReminderPermissionStatus.denied;
      await recovery.refresh();
      repository.permission = ReminderPermissionStatus.unknown;
      await recovery.refresh();
      expect(syncs, 1);
      repository.permission = ReminderPermissionStatus.granted;
      repository.events.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(syncs, 2);
      await recovery.refresh();
      await recovery.refresh();
      expect(syncs, 2);
      recovery.dispose();
      repository.permission = ReminderPermissionStatus.denied;
      await recovery.refresh();
      repository.permission = ReminderPermissionStatus.granted;
      await recovery.refresh();
      expect(syncs, 2);
    },
  );

  test(
    'regrant during initial synchronization queues one non-overlapping pass',
    () async {
      final repository = _Events()
        ..permission = ReminderPermissionStatus.denied;
      final pending = Completer<void>();
      final started = Completer<void>();
      var syncs = 0;
      final recovery = ReminderPermissionRecovery(
        reminders: repository,
        synchronize: () async {
          syncs++;
          if (syncs == 1) {
            started.complete();
            await pending.future;
          }
        },
      );
      addTearDown(recovery.dispose);
      addTearDown(repository.events.close);
      final start = recovery.start();
      await started.future;
      repository.permission = ReminderPermissionStatus.granted;
      await recovery.refresh();
      await recovery.refresh();
      expect(syncs, 1);
      pending.complete();
      await start;
      expect(syncs, 2);
    },
  );

  test('an older permission response cannot hide a later denial', () async {
    final repository = _DelayedPermission();
    var syncs = 0;
    final recovery = ReminderPermissionRecovery(
      reminders: repository,
      synchronize: () async {
        syncs++;
      },
    );
    addTearDown(recovery.dispose);
    final pending = Completer<ReminderPermissionStatus>();
    repository.pending = pending;
    final oldQuery = recovery.refresh();
    repository.pending = null;
    repository.permission = ReminderPermissionStatus.denied;
    await recovery.refresh();
    pending.complete(ReminderPermissionStatus.granted);
    await oldQuery;
    repository.permission = ReminderPermissionStatus.granted;
    await recovery.refresh();
    expect(syncs, 1);
  });

  test(
    'failed synchronization does not lock future permission recovery',
    () async {
      final repository = NoopMeterReminderRepository();
      var syncs = 0;
      final recovery = ReminderPermissionRecovery(
        reminders: repository,
        synchronize: () async {
          if (++syncs == 1) throw StateError('Storage unavailable');
        },
      );
      addTearDown(recovery.dispose);
      await recovery.start();
      repository.permission = ReminderPermissionStatus.denied;
      await recovery.refresh();
      repository.permission = ReminderPermissionStatus.granted;
      await recovery.refresh();
      expect(syncs, 2);
    },
  );
}

class _Events extends NoopMeterReminderRepository {
  final events = StreamController<int>.broadcast();
  @override
  Stream<int> get statusChanges => events.stream;
}

class _DelayedPermission extends NoopMeterReminderRepository {
  Completer<ReminderPermissionStatus>? pending;
  @override
  Future<ReminderPermissionStatus> permissionStatus() =>
      pending?.future ?? super.permissionStatus();
}
