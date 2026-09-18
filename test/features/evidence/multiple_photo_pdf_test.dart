import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final history in [false, true]) {
    test(
      'PDF includes every current photo, excludes archived photos, history=$history',
      () async {
        final temp = await Directory.systemTemp.createTemp('multiple_pdf_');
        addTearDown(() => temp.delete(recursive: true));
        final photos = <ReadingPhotoVersion>[];
        for (var i = 0; i < 4; i++) {
          final file = File('${temp.path}/$i.jpg');
          await file.writeAsBytes(
            img.encodeJpg(
              img.fill(
                img.Image(
                  width: i.isEven ? 30 : 60,
                  height: i.isEven ? 60 : 30,
                ),
                color: img.ColorRgb8(i * 60, 90, 140),
              ),
            ),
          );
          photos.add(
            ReadingPhotoVersion(
              id: 'p$i',
              path: file.path,
              sha256: await const IntegrityService().sha256Bytes(
                await file.readAsBytes(),
              ),
              source: ReadingSource.camera,
              addedAt: DateTime.utc(2026, 9, 16),
              ocrRawText: '',
              ocrCandidate: '',
            ),
          );
        }
        var reading =
            sampleReading(
              path: photos.first.path,
              hash: photos.first.sha256,
            ).copyWith(
              photos: photos.take(3).toList(),
              photoHistory: [photos.last],
              note: 'Notizanfang ${'eine lange Notiz ' * 500} Notizende',
            );
        final assets = _Assets();
        final service = EvidenceReportService(
          exports: MemoryEvidenceExportRepository(),
          documentsDirectoryProvider: () async => temp,
          photoAssets: assets,
        );
        Future<GeneratedEvidenceReport> export(
          MeterReading r,
          EvidencePhotoMode mode,
        ) => history
            ? service.createHistory(
                meter: sampleBook(),
                readings: [r],
                revisions: {},
                photoMode: mode,
              )
            : service.createSingle(reading: r, revisions: [], photoMode: mode);
        final first = await export(reading, EvidencePhotoMode.currentPhotos);
        expect(assets.paths, photos.take(3).map((p) => p.path));
        final originalBytes = await File(first.record.filePath).readAsBytes();
        expect(
          RegExp(
            r'/Subtype\s*/Image',
          ).allMatches(latin1.decode(first.bytes)).length,
          3,
        );
        assets.paths.clear();
        reading = reading.copyWith(
          photos: [photos[2], photos[1]],
          photoHistory: [photos[3], photos[0]],
        );
        final next = await export(reading, EvidencePhotoMode.currentPhotos);
        expect(assets.paths, [photos[2].path, photos[1].path]);
        expect(
          RegExp(
            r'/Subtype\s*/Image',
          ).allMatches(latin1.decode(next.bytes)).length,
          2,
        );
        expect(await File(first.record.filePath).readAsBytes(), originalBytes);
        assets.paths.clear();
        final compact = await export(reading, EvidencePhotoMode.withoutPhotos);
        expect(assets.paths, isEmpty);
        expect(
          RegExp(r'/Subtype\s*/Image').allMatches(latin1.decode(compact.bytes)),
          isEmpty,
        );
        if (const bool.fromEnvironment('PDF_TEXT_AUDIT')) {
          final result = await Process.run('pdftotext', [
            '-layout',
            first.record.filePath,
            '-',
          ]);
          expect(result.exitCode, 0);
          final text = (result.stdout as String).replaceAll(
            RegExp(r'\s+'),
            ' ',
          );
          expect(text, contains('Foto 1 von 3'));
          expect(text, contains('Foto 2 von 3'));
          expect(text, contains('Foto 3 von 3'));
          expect(text, contains('Notizende'));
          expect(text, isNot(contains('Früheres Foto')));
        }
      },
    );
  }
}

class _Assets implements EvidencePhotoAssetRepository {
  final paths = <String>[];
  @override
  Future<String?> prepare({
    required String path,
    required String sha256,
  }) async {
    paths.add(path);
    return path;
  }

  @override
  Future<void> delete(String sha256) async {}
}
