import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';

void main() {
  final reference =
      jsonDecode(
            File(
              'test/parity/pflanzenbuch_processing_reference.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final exceptions =
      jsonDecode(
            File(
              'test/parity/vehicle_processing_exceptions.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final files = (reference['files'] as Map).cast<String, String>();
  final deviations = exceptions['files'] as Map<String, dynamic>;
  test('vehicle exceptions retain original hashes and require coverage', () {
    expect(exceptions['sourceCommit'], reference['sourceCommit']);
    for (final item in deviations.entries) {
      final exception = item.value as Map<String, dynamic>;
      expect(exception['sourceSha256'], files[item.key]);
      expect((exception['reason'] as String).trim(), isNotEmpty);
      final tests = (exception['tests'] as List).cast<String>();
      expect(tests, isNotEmpty);
      for (final path in tests) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    }
  });
  for (final entry in files.entries) {
    test('Pflanzenbuch source or authorized deviation: ${entry.key}', () async {
      final deviation = deviations[entry.key] as Map<String, dynamic>?;
      final path = deviation?['localPath'] as String? ?? entry.key;
      expect(
        await const IntegrityService().sha256Bytes(
          await File(path).readAsBytes(),
        ),
        deviation?['localSha256'] ?? entry.value,
        reason:
            'Preserve original source hashes. Document authorized differences and regression coverage.',
      );
    });
  }
}
