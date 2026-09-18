import '../../features/meters/domain/meter.dart';
import 'local_notification_reminder_repository.dart';

/// Domain data has already been saved. Report notification problems separately.
Future<String?> _readReminderSaveWarning(
  MeterReminderRepository reminders,
  Meter meter,
) async {
  final status = (await reminders.loadStatuses([meter.id]))[meter.id];
  if (status?.planningState == ReminderPlanningState.cancelFailed) {
    return 'Daten gespeichert. Die Erinnerung konnte nicht ausgeschaltet werden. Öffne die Erinnerung und speichere erneut.';
  }
  final schedule = meter.reminder;
  if (schedule == null) return null;
  final available = await reminders.availability(schedule.deliveryMode);
  if (available.isBlocked) {
    return 'Daten gespeichert. Erinnerungen sind in Android blockiert. Öffne die Erinnerung und dann die Android-Einstellungen.';
  }
  if (available == ReminderAvailability.unsupported) {
    return 'Daten gespeichert. Erinnerungen werden auf diesem Gerät nicht unterstützt.';
  }
  if (status?.planningState != ReminderPlanningState.scheduled ||
      status?.nextTriggerAt == null) {
    return 'Daten gespeichert. Die Erinnerung konnte nicht bestätigt werden. Öffne die Erinnerung und speichere erneut.';
  }
  if (schedule.deliveryMode == ReminderDeliveryMode.punctualWithSound &&
      (!await reminders.canScheduleExactAlarms() || status?.isExact == false)) {
    return 'Daten gespeichert. Für eine pünktliche Erinnerung öffne „Alarme & Erinnerungen“ in den Android-Einstellungen.';
  }
  return null;
}

Future<String?> reminderSaveWarning(
  MeterReminderRepository reminders,
  Meter meter,
) async {
  try {
    return await _readReminderSaveWarning(reminders, meter);
  } on Object {
    return 'Daten gespeichert. Der Erinnerungsstatus konnte nicht geprüft werden. Öffne die Erinnerung und speichere erneut.';
  }
}
