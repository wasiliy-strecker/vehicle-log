import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mixed in [false, true]) {
    for (final mode in EvidencePhotoMode.values) {
      test(
        'exports manual reading without empty images or OCR warnings, mixed=$mixed, mode=$mode',
        () async {
          final temp = await Directory.systemTemp.createTemp('manual_pdf_');
          addTearDown(() => temp.delete(recursive: true));
          final photo = File('${temp.path}/photo.jpg');
          await photo.writeAsBytes(
            img.encodeJpg(img.Image(width: 20, height: 20)),
          );
          final manual = sampleReading(
            source: ReadingSource.manual,
            value: '130',
          ).copyWith(note: 'Manuelle Notiz');
          final photographed = sampleReading(
            id: 'earlier',
            path: photo.path,
            value: '85',
          ).copyWith(capturedAt: DateTime.utc(2026, 9, 13, 12));
          final assets = _Assets();
          final service = EvidenceReportService(
            exports: MemoryEvidenceExportRepository(),
            documentsDirectoryProvider: () async => temp,
            photoAssets: assets,
          );
          final report = mixed
              ? await service.createHistory(
                  meter: sampleBook(),
                  readings: [photographed, manual],
                  revisions: const {},
                  photoMode: mode,
                )
              : await service.createSingle(
                  reading: manual,
                  revisions: const [],
                  photoMode: mode,
                );
          expect(report.bytes.take(4), [0x25, 0x50, 0x44, 0x46]);
          expect(
            assets.prepared,
            mixed && mode != EvidencePhotoMode.withoutPhotos
                ? [photo.path]
                : isEmpty,
          );
          if (const bool.fromEnvironment('PDF_TEXT_AUDIT')) {
            final result = await Process.run('pdftotext', [
              '-layout',
              report.record.filePath,
              '-',
            ]);
            expect(result.exitCode, 0, reason: '${result.stderr}');
            final text = (result.stdout as String).replaceAll(
              RegExp(r'\s+'),
              ' ',
            );
            expect(text, isNot(contains('Manuell erfasst')));
            expect(text, contains('Manuelle Notiz'));
            expect(text, contains('130 km'));
            expect(text, isNot(contains('konnte nicht eingebettet werden')));
            if (mixed) {
              expect(text, contains('85 130 = 45 km Differenz'));
            } else {
              expect(text, isNot(contains('OCR-Kandidat')));
              expect(text, isNot(contains('OCR-Konfidenz')));
              expect(text, isNot(contains('Manuell abweichend')));
              expect(text, isNot(contains('Aktuelles Foto hinzugefügt')));
            }
            if (!mixed && mode == EvidencePhotoMode.allPhotos) {
              final audit = await Directory(
                'build/verification',
              ).create(recursive: true);
              await File(
                report.record.filePath,
              ).copy('${audit.path}/fahrzeugakte-manual.pdf');
            }
          }
        },
      );
    }
  }
}

class _Assets extends NoopEvidencePhotoAssetRepository {
  final prepared = <String>[];
  @override
  Future<String?> prepare({
    required String path,
    required String sha256,
  }) async {
    prepared.add(path);
    return path;
  }
}
