import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.appfactory.vehicle_log/reminders');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final repository = LocalNotificationReminderRepository.instance;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final mode in ReminderDeliveryMode.values) {
    for (final state in {
      'available': ReminderAvailability.available,
      'appBlocked': ReminderAvailability.appBlocked,
      'channelBlocked': ReminderAvailability.channelBlocked,
      'unexpected': ReminderAvailability.unknown,
    }.entries) {
      test(
        'queries only the selected $mode channel and reports ${state.value}',
        () async {
          messenger.setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getNotificationAvailability');
            expect(call.arguments, {'deliveryMode': mode.name});
            return state.key;
          });
          expect(await repository.availability(mode), state.value);
        },
      );
    }

    for (final entry in {
      'posted': ReminderTestResult.posted,
      'appBlocked': ReminderTestResult.appBlocked,
      'channelBlocked': ReminderTestResult.channelBlocked,
      'unknown': ReminderTestResult.failed,
      'failed': ReminderTestResult.failed,
    }.entries) {
      test('native test result for $mode is ${entry.value}', () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'areNotificationsEnabled') return true;
          expect(call.method, 'showReminderTest');
          expect((call.arguments as Map)['deliveryMode'], mode.name);
          return entry.key;
        });
        expect(await repository.showReminderTest(_request(mode)), entry.value);
      });
    }
  }

  test('denied permission does not post a test notification', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return false;
    });
    expect(
      await repository.showReminderTest(_request(ReminderDeliveryMode.normal)),
      ReminderTestResult.appBlocked,
    );
    expect(calls, ['areNotificationsEnabled', 'requestNotificationPermission']);
  });

  test(
    'permission granted during the test still checks the selected channel natively',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'areNotificationsEnabled' => false,
          'requestNotificationPermission' => true,
          'showReminderTest' => 'channelBlocked',
          _ => throw StateError(call.method),
        };
      });
      expect(
        await repository.showReminderTest(
          _request(ReminderDeliveryMode.normal),
        ),
        ReminderTestResult.channelBlocked,
      );
      expect(calls, [
        'areNotificationsEnabled',
        'requestNotificationPermission',
        'showReminderTest',
      ]);
    },
  );

  for (final mode in <ReminderDeliveryMode?>[
    null,
    ...ReminderDeliveryMode.values,
  ]) {
    test('opens app or selected channel settings: $mode', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'openNotificationSettings');
        expect(call.arguments, {if (mode != null) 'deliveryMode': mode.name});
        return true;
      });
      expect(await repository.openNotificationSettings(mode: mode), isTrue);
    });
  }

  test(
    'platform failures do not claim a successful test or a known block',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'areNotificationsEnabled') return true;
        throw PlatformException(code: 'unavailable');
      });
      expect(
        await repository.availability(ReminderDeliveryMode.normal),
        ReminderAvailability.unknown,
      );
      expect(
        await repository.showReminderTest(
          _request(ReminderDeliveryMode.normal),
        ),
        ReminderTestResult.failed,
      );
      expect(await repository.openNotificationSettings(), isFalse);
    },
  );

  test('unknown and missing platform responses remain unknown', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(
      await repository.availability(ReminderDeliveryMode.normal),
      ReminderAvailability.unknown,
    );
    expect(
      await repository.showReminderTest(_request(ReminderDeliveryMode.normal)),
      ReminderTestResult.failed,
    );
    expect(await repository.openNotificationSettings(), isFalse);
  });

  test('only posted tests explain how to find the notification', () {
    for (final result in ReminderTestResult.values) {
      for (final quietMode in DoNotDisturbStatus.values) {
        final message = result.message(quietMode);
        expect(
          message.contains('Benachrichtigungsleiste'),
          result == ReminderTestResult.posted,
        );
        expect(
          message.contains('nach einer Minute'),
          result == ReminderTestResult.posted,
        );
        expect(
          message.contains('„Nicht stören“'),
          result == ReminderTestResult.posted &&
              quietMode == DoNotDisturbStatus.enabled,
        );
      }
    }
  });

  test('unsupported platforms do not call Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    expect(
      await repository.availability(ReminderDeliveryMode.normal),
      ReminderAvailability.unsupported,
    );
    expect(
      await repository.showReminderTest(_request(ReminderDeliveryMode.normal)),
      ReminderTestResult.unsupported,
    );
    expect(await repository.openNotificationSettings(), isFalse);
    expect(calls, isEmpty);
  });
}

MeterReminderTestRequest _request(ReminderDeliveryMode mode) =>
    MeterReminderTestRequest(
      label: 'Testbuch',
      meterType: MeterType.electricity,
      deliveryMode: mode,
    );
