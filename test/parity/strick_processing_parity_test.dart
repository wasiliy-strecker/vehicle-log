import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';

void main() {
  // This separate reference preserves the original LeseLog/ZählerLog baseline.
  // No neighboring app checkout is needed to build or test Fahrzeugakte.
  final reference =
      jsonDecode(
            File(
              'test/parity/strick_processing_reference.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final files = (reference['files'] as Map).cast<String, String>();
  final exceptions =
      jsonDecode(
            File(
              'test/parity/vehicle_processing_exceptions.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final deviations = exceptions['files'] as Map<String, dynamic>;
  for (final entry in files.entries) {
    test('shared Strick processing remains identical: ${entry.key}', () async {
      expect(
        await const IntegrityService().sha256Bytes(
          await File(entry.key).readAsBytes(),
        ),
        (deviations[entry.key] as Map<String, dynamic>?)?['localSha256'] ??
            entry.value,
        reason:
            'Reference ${reference['sourceCommit']}. Document intentional changes with regression coverage instead of replacing source hashes.',
      );
    });
  }
}
