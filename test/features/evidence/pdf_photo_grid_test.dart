import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

const _audit = bool.fromEnvironment('PDF_TEXT_AUDIT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final history in [false, true]) {
    for (final count in [0, 1, 2, 3, 4, 5, 12]) {
      test(
        'PDF pairs photos and centers the last odd photo: count=$count, history=$history',
        () async {
          final temp = await Directory.systemTemp.createTemp('photo_grid_');
          addTearDown(() => temp.delete(recursive: true));
          final photos = <ReadingPhotoVersion>[];
          for (var i = 0; i < count; i++) {
            final file = File('${temp.path}/$i.jpg');
            await file.writeAsBytes(
              img.encodeJpg(
                img.fill(
                  img.Image(
                    width: i.isEven ? 100 : 160,
                    height: i.isEven ? 160 : 100,
                  ),
                  color: img.ColorRgb8(30 + i * 15, 100, 150),
                ),
              ),
            );
            photos.add(
              ReadingPhotoVersion(
                id: 'p$i',
                path: file.path,
                sha256: '$i',
                source: ReadingSource.gallery,
                addedAt: DateTime.utc(2026, 9, 16),
                ocrRawText: '',
                ocrCandidate: '',
              ),
            );
          }
          final reading = sampleReading().copyWith(photos: photos);
          final older = sampleReading(id: 'older', source: ReadingSource.manual)
              .copyWith(
                capturedAt: reading.capturedAt.subtract(
                  const Duration(days: 2),
                ),
              );
          final middle =
              sampleReading(
                id: 'middle',
                source: ReadingSource.manual,
              ).copyWith(
                capturedAt: reading.capturedAt.subtract(
                  const Duration(days: 1),
                ),
              );
          final service = EvidenceReportService(
            exports: MemoryEvidenceExportRepository(),
            documentsDirectoryProvider: () async => temp,
            photoAssets: _Assets(),
          );
          final report = history
              ? await service.createHistory(
                  meter: sampleBook(),
                  readings: [older, reading, middle],
                  revisions: {},
                )
              : await service.createSingle(reading: reading, revisions: []);
          expect(
            RegExp(
              r'/Subtype\s*/Image',
            ).allMatches(latin1.decode(report.bytes)),
            hasLength(count),
          );
          if (!_audit) return;
          final result = await Process.run('pdftohtml', [
            '-xml',
            '-zoom',
            '1',
            '-hidden',
            '-stdout',
            report.record.filePath,
          ], workingDirectory: temp.path);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          final pages = RegExp(
            r'<page\s+([^>]+)>(.*?)</page>',
            dotAll: true,
          ).allMatches(result.stdout as String).toList();
          final images = <Map<String, double>>[];
          final captions = <String, Map<String, double>>{};
          final readingHeadings = <String>[];
          for (final page in pages) {
            final pageAttrs = _attributes(page.group(1)!);
            final pageNumber = double.parse(pageAttrs['number']!);
            for (final match in RegExp(
              r'<image\s+([^>]+)>',
            ).allMatches(page.group(2)!)) {
              final a = _attributes(match.group(1)!);
              images.add({
                for (final key in ['left', 'top', 'width', 'height'])
                  key: double.parse(a[key]!),
                'page': pageNumber,
                'pageWidth': double.parse(pageAttrs['width']!),
              });
            }
            for (final match in RegExp(
              r'<text\s+([^>]+)>(.*?)</text>',
              dotAll: true,
            ).allMatches(page.group(2)!)) {
              final text = match.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '');
              if (RegExp(r'^Eintrag \d+').hasMatch(text)) {
                readingHeadings.add(text);
              }
              final a = _attributes(match.group(1)!);
              captions[text] = {
                'top': double.parse(a['top']!),
                'height': double.parse(a['height']!),
                'page': pageNumber,
              };
            }
          }
          expect(images, hasLength(count));
          expect(
            readingHeadings,
            hasLength(count == 0 ? (history ? 0 : 1) : (count + 1) ~/ 2),
          );
          for (final heading in readingHeadings) {
            expect(
              heading,
              startsWith('Eintrag ${history ? 3 : 1}'),
              reason:
                  'Compact entries count towards photo continuation numbers',
            );
          }
          for (var i = 0; i < count; i++) {
            final image = images[i];
            final cellWidth = (image['pageWidth']! - 80 - 12) / 2;
            final isLastOdd = count.isOdd && i == count - 1;
            final expectedCenter = isLastOdd
                ? image['pageWidth']! / 2
                : 40 + cellWidth / 2 + (i.isOdd ? cellWidth + 12 : 0);
            expect(
              image['left']! + image['width']! / 2,
              closeTo(expectedCenter, 1),
            );
            expect(image['width']!, lessThanOrEqualTo(cellWidth + 1));
            expect(image['height']!, lessThanOrEqualTo(171));
            expect(
              image['width']! / image['height']!,
              closeTo(i.isEven ? 100 / 160 : 160 / 100, .02),
            );
            final caption = captions['Foto ${i + 1} von $count']!;
            expect(caption['page'], image['page']);
            expect(
              caption['top']! + caption['height']!,
              lessThan(image['top']!),
            );
            if (i.isOdd) {
              final previous = images[i - 1];
              expect(image['page'], previous['page']);
              expect(
                image['top']! + image['height']! / 2,
                closeTo(previous['top']! + previous['height']! / 2, 1),
              );
            }
            if (i == 0) {
              final heading = captions['Kilometerstand']!;
              expect(heading['page'], image['page']);
              expect(
                heading['top']! + heading['height']!,
                lessThan(image['top']!),
              );
            }
          }
          if (!history && count == 3) {
            final verification = await Directory(
              'build/verification',
            ).create(recursive: true);
            await File(
              report.record.filePath,
            ).copy('${verification.path}/fahrzeugakte-grid-single-3.pdf');
            await File(
              '${verification.path}/fahrzeugakte-grid-single-3.xml',
            ).writeAsString(result.stdout as String);
            expect(
              pages,
              hasLength(2),
              reason:
                  'The extra care row moves the second photo row to the next page without splitting it',
            );
          }
        },
      );
    }
  }

  test(
    'missing middle photo keeps its numbered cell and other photos',
    () async {
      final temp = await Directory.systemTemp.createTemp('missing_grid_');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/photo.jpg')
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 100, height: 160)));
      final photos = List.generate(
        3,
        (i) => ReadingPhotoVersion(
          id: 'p$i',
          path: i == 1 ? '${temp.path}/missing.jpg' : file.path,
          sha256: '$i',
          source: ReadingSource.camera,
          addedAt: DateTime.utc(2026),
          ocrRawText: '',
          ocrCandidate: '',
        ),
      );
      final report =
          await EvidenceReportService(
            exports: MemoryEvidenceExportRepository(),
            documentsDirectoryProvider: () async => temp,
            photoAssets: _Assets(),
          ).createSingle(
            reading: sampleReading().copyWith(photos: photos),
            revisions: [],
          );
      expect(report.bytes, isNotEmpty);
      if (_audit) {
        final result = await Process.run('pdftotext', [
          '-layout',
          report.record.filePath,
          '-',
        ]);
        expect(result.exitCode, 0);
        final text = (result.stdout as String).replaceAll(RegExp(r'\s+'), ' ');
        for (final label in [
          'Foto 1 von 3',
          'Foto 2 von 3',
          'Foto 3 von 3',
          'Fahrzeugfoto konnte nicht eingebettet werden.',
        ]) {
          expect(text, contains(label));
        }
      }
    },
  );
}

Map<String, String> _attributes(String raw) => {
  for (final match in RegExp(r'([\w-]+)="([^"]*)"').allMatches(raw))
    match.group(1)!: match.group(2)!,
};

class _Assets implements EvidencePhotoAssetRepository {
  @override
  Future<String?> prepare({
    required String path,
    required String sha256,
  }) async => File(path).existsSync() ? path : null;
  @override
  Future<void> delete(String sha256) async {}
}
