import 'package:flutter/material.dart';

import '../../../app/widgets/app_snack_bar.dart';
import '../../../core/reminders/local_notification_reminder_repository.dart';
import '../../../core/reminders/reminder_delivery_state.dart';
import '../domain/meter.dart';

class ReminderDeliveryHint extends StatelessWidget {
  const ReminderDeliveryHint({
    super.key,
    required this.state,
    required this.mode,
    required this.onOpenSettings,
  });

  final ReminderDeliveryState state;
  final ReminderDeliveryMode mode;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = state.appBlocked
        ? 'Benachrichtigungen sind ausgeschaltet'
        : state.channelBlocked
        ? 'Diese Erinnerungsart ist ausgeschaltet'
        : '„Nicht stören“ ist aktiv';
    final message = state.appBlocked
        ? 'Android blockiert Benachrichtigungen für Fahrzeugakte. '
              'Du kannst sie in den Android-Einstellungen erlauben.'
        : state.channelBlocked
        ? 'Android blockiert „${mode == ReminderDeliveryMode.normal ? 'Fahrzeugerinnerungen' : 'Pünktliche Fahrzeugerinnerungen'}“. '
              'Du kannst diese Kategorie in den Android-Einstellungen einschalten.'
        : mode == ReminderDeliveryMode.normal
        ? 'Normale Erinnerungen können ohne Ton oder eingeblendetes Banner erscheinen. '
              'Prüfe auch die Benachrichtigungsleiste.'
        : 'Ob ein Alarmton oder Banner erscheint, hängt von deinen '
              '„Nicht stören“-Einstellungen und der Alarmlautstärke ab.';
    return Container(
      key: const ValueKey('reminder-delivery-hint'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                state.blocked
                    ? Icons.notifications_off_outlined
                    : Icons.bedtime_outlined,
                color: colors.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpenSettings,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 56),
              foregroundColor: colors.onSecondaryContainer,
              side: BorderSide(color: colors.onSecondaryContainer),
            ),
            icon: const Icon(Icons.settings_outlined),
            label: Text(
              state.blocked
                  ? 'Android-Einstellungen öffnen'
                  : '„Nicht stören“ öffnen',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openReminderSettings({
  required ScaffoldMessengerState messenger,
  required MeterReminderRepository reminders,
  bool doNotDisturb = false,
  ReminderDeliveryMode? mode,
}) async {
  var opened = false;
  try {
    opened = doNotDisturb
        ? await reminders.openDoNotDisturbSettings()
        : await reminders.openNotificationSettings(mode: mode);
  } on Object {
    // A settings failure must leave the form usable.
  }
  if (opened || !messenger.mounted) return;
  messenger.showSnackBar(
    AppSnackBar(
      message: doNotDisturb
          ? 'Die Systemeinstellungen konnten nicht geöffnet werden. '
                'Suche in den Einstellungen deines Smartphones nach „Nicht stören“.'
          : 'Die Systemeinstellungen konnten nicht geöffnet werden. '
                'Öffne in den Einstellungen deines Smartphones „Apps“, '
                'dann „Fahrzeugakte“ und „Benachrichtigungen“.',
    ),
  );
}
