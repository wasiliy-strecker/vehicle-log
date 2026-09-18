import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/app/app_theme.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_form_screen.dart';

import '../../support/contrast_expectations.dart';
import '../../support/fakes.dart';

const _title = '„Nicht stören“ ist aktiv';
const _normalHint =
    'Normale Erinnerungen können ohne Ton oder eingeblendetes Banner erscheinen. Prüfe auch die Benachrichtigungsleiste.';
const _alarmHint =
    'Ob ein Alarmton oder Banner erscheint, hängt von deinen „Nicht stören“-Einstellungen und der Alarmlautstärke ab.';
const _testFeedback =
    'Test-Erinnerung wurde an Android übergeben. Ziehe die Benachrichtigungsleiste herunter. Die Test-Erinnerung verschwindet nach einer Minute. „Nicht stören“ ist aktiv. Ton und Banner können unterdrückt werden.';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('quiet-mode hint is readable in $brightness at $scale', (
        tester,
      ) async {
        final reminders = NoopMeterReminderRepository(
          doNotDisturb: DoNotDisturbStatus.enabled,
        );
        await _pump(tester, reminders, brightness: brightness, scale: scale);
        final settings = find.widgetWithText(
          OutlinedButton,
          '„Nicht stören“ öffnen',
        );
        await _reveal(tester, settings);
        await tester.pumpAndSettle();

        expect(find.text(_title), findsOneWidget);
        expect(find.text(_normalHint), findsOneWidget);
        expectReadable(tester, find.text(_title));
        expectReadable(tester, find.text(_normalHint));
        expectReadable(tester, find.text('„Nicht stören“ öffnen'));
        expectReadable(tester, find.byIcon(Icons.bedtime_outlined), minimum: 3);
        final material = find.descendant(
          of: settings,
          matching: find.byType(Material),
        );
        expect(tester.getSize(material).height, greaterThanOrEqualTo(56));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('„Nicht stören“ öffnen'),
            matching: find.byType(RichText),
          ),
        );
        expect(paragraph.textAlign, TextAlign.center);
        expect(tester.takeException(), isNull);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(reminders.doNotDisturbSettingsOpenCount, 1);
      });
    }
  }

  for (final state in [
    DoNotDisturbStatus.disabled,
    DoNotDisturbStatus.unknown,
  ]) {
    testWidgets('no quiet-mode warning for $state', (tester) async {
      await _pump(tester, NoopMeterReminderRepository(doNotDisturb: state));
      await _reveal(tester, find.text('Erinnerung jetzt testen'));
      expect(find.text(_title), findsNothing);
      expect(find.text('„Nicht stören“ öffnen'), findsNothing);
    });
  }

  testWidgets('returning from settings refreshes the hint and keeps edits', (
    tester,
  ) async {
    final reminders = NoopMeterReminderRepository();
    await _pump(tester, reminders);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Fahrzeugname *'),
      'Mein geänderter Titel',
    );
    reminders.doNotDisturb = DoNotDisturbStatus.enabled;
    await _resume(tester);
    await _reveal(tester, find.text('Erinnerung jetzt testen'));
    expect(find.text(_title), findsOneWidget);

    reminders.doNotDisturb = DoNotDisturbStatus.disabled;
    await _resume(tester);
    expect(find.text(_title), findsNothing);
    await _reveal(
      tester,
      find.widgetWithText(TextFormField, 'Fahrzeugname *'),
      delta: -250,
    );
    expect(find.text('Mein geänderter Titel'), findsOneWidget);
  });

  for (final mode in ReminderDeliveryMode.values) {
    testWidgets('test refreshes quiet mode and explains delivery for $mode', (
      tester,
    ) async {
      final reminders = NoopMeterReminderRepository();
      await _pump(tester, reminders, mode: mode);
      // Mode changed while the app was open: test must query it again.
      reminders.doNotDisturb = DoNotDisturbStatus.enabled;
      final testButton = find.text('Erinnerung jetzt testen');
      await _reveal(tester, testButton);
      await tester.tap(testButton);
      await tester.pumpAndSettle();

      expect(reminders.reminderTests.single.deliveryMode, mode);
      expect(find.text(_testFeedback), findsOneWidget);
      expect(
        find.text(
          mode == ReminderDeliveryMode.normal ? _normalHint : _alarmHint,
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'notification permission failure takes precedence over quiet mode',
    (tester) async {
      await _pump(
        tester,
        NoopMeterReminderRepository(
          doNotDisturb: DoNotDisturbStatus.enabled,
          reminderTestResult: ReminderTestResult.appBlocked,
          permission: ReminderPermissionStatus.denied,
        ),
      );
      final testButton = find.text('Erinnerung jetzt testen');
      await _reveal(tester, testButton);
      await tester.tap(testButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Benachrichtigungen sind nicht erlaubt.'),
        findsOneWidget,
      );
      expect(find.text(_testFeedback), findsNothing);
    },
  );

  testWidgets('settings failure tells the user where to find quiet mode', (
    tester,
  ) async {
    await _pump(
      tester,
      NoopMeterReminderRepository(
        doNotDisturb: DoNotDisturbStatus.enabled,
        doNotDisturbSettingsOpenResult: false,
      ),
    );
    final settings = find.text('„Nicht stören“ öffnen');
    await _reveal(tester, settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Die Systemeinstellungen konnten nicht geöffnet werden.',
      ),
      findsOneWidget,
    );
  });

  for (final state in [
    ReminderAvailability.appBlocked,
    ReminderAvailability.channelBlocked,
  ]) {
    for (final mode in ReminderDeliveryMode.values) {
      testWidgets(
        'blocked $state in $mode links to the right settings and has no success claim',
        (tester) async {
          final reminders = NoopMeterReminderRepository(
            normalAvailability: state,
            punctualAvailability: state,
            reminderTestResult: state == ReminderAvailability.appBlocked
                ? ReminderTestResult.appBlocked
                : ReminderTestResult.channelBlocked,
          );
          await _pump(tester, reminders, mode: mode);
          final settings = find.text('Android-Einstellungen öffnen');
          await _reveal(tester, settings);
          await tester.tap(settings);
          await tester.pumpAndSettle();
          expect(reminders.notificationSettingsOpened, [
            state == ReminderAvailability.appBlocked ? null : mode,
          ]);

          await _reveal(tester, find.text('Erinnerung jetzt testen'));
          await tester.tap(find.text('Erinnerung jetzt testen'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Ziehe die Benachrichtigungsleiste herunter.'),
            findsNothing,
          );
          expect(
            find.textContaining('wurde an Android übergeben.'),
            findsNothing,
          );
          expect(
            find.text(
              state == ReminderAvailability.appBlocked
                  ? 'Benachrichtigungen sind nicht erlaubt.'
                  : 'Diese Erinnerungsart ist in Android gesperrt.',
            ),
            findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets(
    'channel warning follows the selected mode and refreshes after settings',
    (tester) async {
      final reminders = NoopMeterReminderRepository(
        normalAvailability: ReminderAvailability.channelBlocked,
      );
      await _pump(tester, reminders);
      await _reveal(tester, find.text('Android-Einstellungen öffnen'));
      expect(
        find.textContaining('Android blockiert „Fahrzeugerinnerungen“.'),
        findsOneWidget,
      );

      await _reveal(tester, find.text('Pünktlich mit Ton'), delta: -250);
      await tester.tap(find.text('Pünktlich mit Ton'));
      await tester.pumpAndSettle();
      expect(find.text('Android-Einstellungen öffnen'), findsNothing);

      await _reveal(tester, find.text('Normale Erinnerung'), delta: -250);
      await tester.tap(find.text('Normale Erinnerung'));
      await tester.pumpAndSettle();
      expect(find.text('Android-Einstellungen öffnen'), findsOneWidget);
      reminders.normalAvailability = ReminderAvailability.available;
      await _resume(tester);
      expect(find.text('Android-Einstellungen öffnen'), findsNothing);
    },
  );

  for (final state in [
    ReminderAvailability.unknown,
    ReminderAvailability.unsupported,
  ]) {
    testWidgets('does not invent a notification block for $state', (
      tester,
    ) async {
      await _pump(
        tester,
        NoopMeterReminderRepository(normalAvailability: state),
      );
      await _reveal(tester, find.text('Erinnerung jetzt testen'));
      expect(find.text('Android-Einstellungen öffnen'), findsNothing);
    });
  }

  testWidgets('failed notification settings show a useful fallback', (
    tester,
  ) async {
    await _pump(
      tester,
      NoopMeterReminderRepository(
        normalAvailability: ReminderAvailability.appBlocked,
        notificationSettingsOpenResult: false,
      ),
    );
    await _reveal(tester, find.text('Android-Einstellungen öffnen'));
    await tester.tap(find.text('Android-Einstellungen öffnen'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Die Systemeinstellungen konnten nicht geöffnet werden.',
      ),
      findsOneWidget,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'blocked reminder hint fits large text in $brightness with readable centered button',
      (tester) async {
        await _pump(
          tester,
          NoopMeterReminderRepository(
            normalAvailability: ReminderAvailability.channelBlocked,
          ),
          brightness: brightness,
          scale: 2,
        );
        final button = find.widgetWithText(
          OutlinedButton,
          'Android-Einstellungen öffnen',
        );
        await _reveal(tester, button);
        expectReadable(
          tester,
          find.text('Diese Erinnerungsart ist ausgeschaltet'),
        );
        expectReadable(
          tester,
          find.textContaining('Android blockiert „Fahrzeugerinnerungen“.'),
        );
        expectReadable(tester, find.text('Android-Einstellungen öffnen'));
        expectReadable(
          tester,
          find.byIcon(Icons.notifications_off_outlined),
          minimum: 3,
        );
        expect(
          tester
              .getSize(
                find.descendant(of: button, matching: find.byType(Material)),
              )
              .height,
          greaterThanOrEqualTo(56),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('Android-Einstellungen öffnen'),
            matching: find.byType(RichText),
          ),
        );
        expect(paragraph.textAlign, TextAlign.center);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  NoopMeterReminderRepository reminders, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  ReminderDeliveryMode mode = ReminderDeliveryMode.normal,
}) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final meter = Meter(
    id: 'book',
    label: 'Testbuch',
    type: MeterType.electricity,
    unit: 'km',
    meterNumber: '',
    location: '',
    createdAt: DateTime.utc(2026, 9, 16),
    updatedAt: DateTime.utc(2026, 9, 16),
    reminder: ReadingReminderSchedule(
      interval: ReminderInterval.daily,
      day: 1,
      hour: 9,
      minute: 0,
      deliveryMode: mode,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        meterRepositoryProvider.overrideWithValue(
          MemoryMeterRepository()..items[meter.id] = meter,
        ),
        meterReadingRepositoryProvider.overrideWithValue(
          MemoryReadingRepository(),
        ),
        meterReminderRepositoryProvider.overrideWithValue(reminders),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: MeterFormScreen(meterId: meter.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
