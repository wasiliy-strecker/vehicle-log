import '../../features/meters/domain/meter.dart';
import 'local_notification_reminder_repository.dart';

class ReminderDeliveryState {
  const ReminderDeliveryState({
    this.availability = ReminderAvailability.unknown,
    this.doNotDisturb = DoNotDisturbStatus.unknown,
  });

  final ReminderAvailability availability;
  final DoNotDisturbStatus doNotDisturb;

  bool get appBlocked => availability == ReminderAvailability.appBlocked;
  bool get channelBlocked =>
      availability == ReminderAvailability.channelBlocked;
  bool get blocked => appBlocked || channelBlocked;
  bool get hasHint => blocked || doNotDisturb == DoNotDisturbStatus.enabled;

  static Future<ReminderDeliveryState> read(
    MeterReminderRepository repository,
    ReminderDeliveryMode mode,
  ) async {
    final values = await Future.wait<Object>([
      _readOr(
        () => repository.availability(mode),
        ReminderAvailability.unknown,
      ),
      _readOr(repository.doNotDisturbStatus, DoNotDisturbStatus.unknown),
    ]);
    return ReminderDeliveryState(
      availability: values[0] as ReminderAvailability,
      doNotDisturb: values[1] as DoNotDisturbStatus,
    );
  }

  static Future<T> _readOr<T>(Future<T> Function() read, T fallback) async {
    try {
      return await read();
    } on Object {
      return fallback;
    }
  }
}
