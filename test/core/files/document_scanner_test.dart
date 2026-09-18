import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_document_scanner');
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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
  });
}
