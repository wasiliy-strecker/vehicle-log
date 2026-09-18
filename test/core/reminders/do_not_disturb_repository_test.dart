import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';

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

  for (final entry in <bool?, DoNotDisturbStatus>{
    true: DoNotDisturbStatus.enabled,
    false: DoNotDisturbStatus.disabled,
    null: DoNotDisturbStatus.unknown,
  }.entries) {
    test('reads ${entry.value} without requesting any permission', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return entry.key;
      });

      expect(await repository.doNotDisturbStatus(), entry.value);
      expect(calls, ['getDoNotDisturbStatus']);
    });
  }

  test('an unavailable Android API is unknown, not disabled', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(await repository.doNotDisturbStatus(), DoNotDisturbStatus.unknown);
    expect(await repository.openDoNotDisturbSettings(), isFalse);
  });

  test('an older native installation is handled without failing', () async {
    expect(await repository.doNotDisturbStatus(), DoNotDisturbStatus.unknown);
    expect(await repository.openDoNotDisturbSettings(), isFalse);
  });

  for (final opened in [true, false]) {
    test('reports whether Android could open settings: $opened', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'openDoNotDisturbSettings');
        return opened;
      });
      expect(await repository.openDoNotDisturbSettings(), opened);
    });
  }

  test('unsupported platforms do not invoke Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    expect(await repository.doNotDisturbStatus(), DoNotDisturbStatus.unknown);
    expect(await repository.openDoNotDisturbSettings(), isFalse);
    expect(calls, isEmpty);
  });
}
