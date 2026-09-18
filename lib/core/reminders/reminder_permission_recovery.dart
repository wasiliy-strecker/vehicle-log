import 'dart:async';

import 'local_notification_reminder_repository.dart';

/// Reconcile persisted schedules when Android notifications are allowed again.
class ReminderPermissionRecovery {
  ReminderPermissionRecovery({
    required this.reminders,
    required this.synchronize,
  });

  final MeterReminderRepository reminders;
  final Future<void> Function() synchronize;
  StreamSubscription<int>? _subscription;
  int _query = 0;
  bool _wasDenied = false;
  bool _disposed = false;
  bool _synchronizing = false;
  bool _syncRequested = false;

  Future<void> start() async {
    _subscription = reminders.statusChanges.listen((_) => unawaited(refresh()));
    await refresh();
    if (!_disposed) await _synchronize();
  }

  Future<void> refresh() async {
    final query = ++_query;
    ReminderPermissionStatus permission;
    try {
      permission = await reminders.permissionStatus();
    } on Object {
      return;
    }
    if (_disposed || query != _query) return;
    if (permission == ReminderPermissionStatus.denied) {
      _wasDenied = true;
    } else if (permission == ReminderPermissionStatus.granted && _wasDenied) {
      _wasDenied = false;
      await _synchronize();
    }
  }

  Future<void> _synchronize() async {
    _syncRequested = true;
    if (_synchronizing) return;
    _synchronizing = true;
    try {
      while (_syncRequested && !_disposed) {
        _syncRequested = false;
        await synchronize();
      }
    } on Object {
      // Opening the app/settings must remain possible if local storage fails.
      // The next permission recovery or app start can try again.
    } finally {
      _synchronizing = false;
    }
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
  }
}
