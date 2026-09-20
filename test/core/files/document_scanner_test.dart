import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_document_scanner');
  const lifecycle = MethodChannel(
    'com.appfactory.vehicle_log/document_scan_lifecycle',
  );
  late List<String> lifecycleCalls;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    lifecycleCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lifecycle, (call) async {
          lifecycleCalls.add(call.method);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lifecycle, null);
  });

  test(
    'scanner uses Contract Manager multi-page settings and returns the PDF',
    () async {
      var closed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'vision#closeDocumentScanner') {
              closed = true;
              return null;
            }
            final options = (call.arguments as Map)['options'] as Map;
            expect(options['pageLimit'], 20);
            expect(options['mode'], 'full');
            expect(options['isGalleryImport'], isFalse);
            expect(options['formats'], containsAll(['jpeg', 'pdf']));
            return {
              'images': <String>[],
              'pdf': {
                'uri': 'file:///tmp/synthetic%20scan.pdf',
                'pageCount': 3,
              },
            };
          });
      expect(
        await const AndroidDocumentScannerRepository().scan(),
        '/tmp/synthetic scan.pdf',
      );
      expect(closed, isTrue);
      expect(lifecycleCalls, ['begin', 'finish']);
    },
  );

  test('cancel is harmless and releases the scanner', () async {
    var closed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'vision#closeDocumentScanner') {
            closed = true;
            return null;
          }
          throw PlatformException(
            code: 'DocumentScanner',
            message: 'Operation cancelled',
          );
        });
    expect(await const AndroidDocumentScannerRepository().scan(), isNull);
    expect(closed, isTrue);
    expect(lifecycleCalls, ['begin', 'finish']);
  });

  test('unavailable scanner preserves a useful import fallback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'vision#closeDocumentScanner') return null;
          throw PlatformException(code: 'DocumentScanner', message: 'Failed');
        });
    await expectLater(
      const AndroidDocumentScannerRepository().scan(),
      throwsA(
        isA<FormatException>()
            .having((e) => e.message, 'RAM', contains('1,7 GB'))
            .having((e) => e.message, 'fallback', contains('PDF auswählen')),
      ),
    );
    expect(lifecycleCalls, ['begin', 'finish']);
  });

  test('a missing PDF is an error and releases the lifecycle guard', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'vision#closeDocumentScanner') return null;
          return {'images': <String>[], 'pdf': null};
        });
    await expectLater(
      const AndroidDocumentScannerRepository().scan(),
      throwsFormatException,
    );
    expect(lifecycleCalls, ['begin', 'finish']);
  });

  test('cleanup failure does not lose a successfully scanned PDF', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'vision#closeDocumentScanner') {
            throw PlatformException(code: 'cleanup_failed');
          }
          return {
            'images': <String>[],
            'pdf': {'uri': '/tmp/completed.pdf', 'pageCount': 1},
          };
        });
    expect(
      await const AndroidDocumentScannerRepository().scan(),
      '/tmp/completed.pdf',
    );
    expect(lifecycleCalls, ['begin', 'finish']);
  });
}
