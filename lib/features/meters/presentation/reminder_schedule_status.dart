import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../app/widgets/app_snack_bar.dart';
import '../../../core/reminders/local_notification_reminder_repository.dart';
import '../../../core/utils/formatters.dart';
import '../domain/meter.dart';

final reminderAvailabilityProvider = FutureProvider.autoDispose
    .family<ReminderAvailability, ReminderDeliveryMode>((ref, mode) async {
      ref.watch(reminderStatusChangesProvider);
      return ref.watch(meterReminderRepositoryProvider).availability(mode);
    });

final exactReminderPermissionProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(reminderStatusChangesProvider);
  return ref.watch(meterReminderRepositoryProvider).canScheduleExactAlarms();
});

class ReminderScheduleStatus extends ConsumerWidget {
  const ReminderScheduleStatus({
    super.key,
    required this.meterId,
    required this.deliveryMode,
    this.status,
    required this.accentColor,
  });

  final String meterId;
  final ReminderDeliveryMode deliveryMode;
  final ReminderStatus? status;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability =
        ref.watch(reminderAvailabilityProvider(deliveryMode)).value ??
        ReminderAvailability.unknown;
    final exactPermission =
        deliveryMode == ReminderDeliveryMode.punctualWithSound
        ? ref.watch(exactReminderPermissionProvider).value
        : true;
    final exactMissing =
        deliveryMode == ReminderDeliveryMode.punctualWithSound &&
        exactPermission == false;
    final inexact =
        deliveryMode == ReminderDeliveryMode.punctualWithSound &&
        exactPermission == true &&
        status?.isExact == false;
    final state = status?.planningState ?? ReminderPlanningState.unknown;
    final next = status?.nextTriggerAt;
    final failed =
        state == ReminderPlanningState.failed ||
        state == ReminderPlanningState.none;
    final cancelFailed = state == ReminderPlanningState.cancelFailed;
    final deliveryFailed = status?.deliveryFailed ?? false;
    final known = state == ReminderPlanningState.scheduled && next != null;
    final due = known && !next.isAfter(DateTime.now());
    final String title;
    final String description;
    if (cancelFailed) {
      title = 'Ausschalten fehlgeschlagen';
      description = 'Bitte öffne die Erinnerung und speichere erneut.';
    } else if (availability.isBlocked) {
      title = 'Erinnerung blockiert';
      description = availability == ReminderAvailability.appBlocked
          ? 'Benachrichtigungen sind ausgeschaltet.'
          : 'Diese Erinnerungsart ist ausgeschaltet.';
    } else if (availability == ReminderAvailability.unsupported) {
      title = 'Erinnerungen nicht unterstützt';
      description =
          'Auf diesem Gerät können keine Erinnerungen angezeigt werden.';
    } else if (failed) {
      title = 'Erinnerung nicht geplant';
      description = 'Bitte öffne die Erinnerung und speichere erneut.';
    } else if (exactMissing) {
      title = 'Pünktlichkeit nicht erlaubt';
      description =
          'Erlaube „Alarme & Erinnerungen“ in Android. Bis dahin kann die Erinnerung verspätet erscheinen.';
    } else if (inexact) {
      title = 'Pünktliche Planung ausstehend';
      description =
          'Der Termin ist noch ungenau geplant. Öffne die Erinnerung und speichere erneut.';
    } else if (deliveryFailed) {
      title = 'Letzte Zustellung fehlgeschlagen';
      description =
          'Bitte öffne die Erinnerung und nutze „Erinnerung jetzt testen“.';
    } else if (!known ||
        availability != ReminderAvailability.available ||
        exactPermission == null) {
      title = 'Planungsstatus unbekannt';
      description =
          'Der Erinnerungsstatus konnte nicht bestätigt werden. Öffne die Erinnerung zum Prüfen.';
    } else {
      title = due ? 'Erinnerung steht noch aus' : 'Nächste Erinnerung';
      description =
          '${formatDateTime(next)} Uhr${due ? '. Android hat diesen Termin noch nicht verarbeitet.' : ''}';
    }
    final repair =
        cancelFailed ||
        failed ||
        deliveryFailed ||
        inexact ||
        !known ||
        availability == ReminderAvailability.unknown ||
        exactPermission == null;
    final settingsAction =
        !cancelFailed && (availability.isBlocked || (!failed && exactMissing));
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final blocked =
        availability.isBlocked ||
        failed ||
        cancelFailed ||
        exactMissing ||
        deliveryFailed;
    final unsupported = availability == ReminderAvailability.unsupported;
    final foreground = blocked ? colors.onErrorContainer : colors.onSurface;
    return Container(
      key: ValueKey('next-reminder-$meterId'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: blocked
            ? colors.errorContainer
            : accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: blocked ? colors.error : accentColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                blocked || unsupported
                    ? Icons.notifications_off_outlined
                    : Icons.schedule_outlined,
                size: 20,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: blocked || unsupported
                            ? FontWeight.normal
                            : FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!unsupported &&
              (availability.isBlocked || exactMissing || repair)) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 50),
                foregroundColor: foreground,
                side: BorderSide(color: foreground),
              ),
              onPressed: settingsAction
                  ? () => _openSettings(
                      context,
                      ref,
                      availability,
                      exactMissing: exactMissing && !availability.isBlocked,
                    )
                  : () => context.pushNamed(
                      'meterEdit',
                      pathParameters: {'id': meterId},
                    ),
              icon: const Icon(Icons.settings_outlined),
              label: Text(
                settingsAction
                    ? 'Einstellungen öffnen'
                    : 'Erinnerung bearbeiten',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openSettings(
    BuildContext context,
    WidgetRef ref,
    ReminderAvailability availability, {
    bool exactMissing = false,
  }) async {
    var opened = false;
    try {
      final repository = ref.read(meterReminderRepositoryProvider);
      opened = exactMissing
          ? await repository.openExactAlarmSettings()
          : await repository.openNotificationSettings(
              mode: availability == ReminderAvailability.channelBlocked
                  ? deliveryMode
                  : null,
            );
    } on Object {
      // Preserve a usable manual path if Android cannot open its settings.
    }
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      AppSnackBar(
        message: exactMissing
            ? 'Die Einstellungen konnten nicht geöffnet werden. Suche in den Einstellungen deines Smartphones nach „Alarme & Erinnerungen“ und wähle diese App.'
            : 'Die Einstellungen konnten nicht geöffnet werden. Öffne in den '
                  'Einstellungen deines Smartphones „Apps“, wähle diese App und '
                  'dann „Benachrichtigungen“.',
      ),
    );
  }
}
