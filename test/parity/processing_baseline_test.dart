import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';

// Pinned source hashes keep this check independent of any neighboring checkout.
// Branding-bearing files are reviewed separately; see docs/PROCESSING_PARITY.md.
void main() {
  final baseline =
      jsonDecode(
            File('test/parity/processing_baseline.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final files = (baseline['files'] as Map).cast<String, String>();
  final exceptions =
      jsonDecode(
            File('test/parity/processing_exceptions.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final deviations = exceptions['files'] as Map<String, dynamic>;

  test(
    'authorized exceptions retain source hashes and require regression tests',
    () {
      expect(exceptions['sourceCommit'], baseline['sourceCommit']);
      expect(deviations, isNotEmpty);
      for (final entry in deviations.entries) {
        final exception = entry.value as Map<String, dynamic>;
        expect(files, contains(entry.key));
        expect(exception['sourceSha256'], files[entry.key]);
        expect(exception['localSha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(exception['localSha256'], isNot(files[entry.key]));
        expect((exception['reason'] as String).trim(), isNotEmpty);
        final tests = (exception['tests'] as List).cast<String>();
        expect(tests, isNotEmpty);
        for (final path in tests) {
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
    },
  );
  for (final entry in files.entries) {
    test('ZählerLog processing baseline: ${entry.key}', () async {
      expect(
        await const IntegrityService().sha256Bytes(
          await File(entry.key).readAsBytes(),
        ),
        (deviations[entry.key] as Map<String, dynamic>?)?['localSha256'] ??
            entry.value,
        reason:
            'Processing must match source ${baseline['sourceCommit']}. '
            'Authorized bugfixes require a documented exception with regression tests; '
            'the frozen source hashes must not be overwritten.',
      );
    });
  }
}
