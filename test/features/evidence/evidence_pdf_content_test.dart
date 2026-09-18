import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';

// The regular suite needs only Dart/Flutter. Additionally inspect the actual
// generated documents with Poppler installed:
// flutter test --dart-define=PDF_TEXT_AUDIT=true test/features/evidence/evidence_pdf_content_test.dart
const _auditPdfText = bool.fromEnvironment('PDF_TEXT_AUDIT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reading times use the saved offset including date rollovers', () {
    final date = DateFormat('dd.MM.yyyy, HH:mm');
    for (final sample in [
      (DateTime.utc(2026, 9, 13, 10), 120, '13.09.2026, 12:00 (UTC+02:00)'),
      (DateTime.utc(2026, 1, 1, 23, 30), 60, '02.01.2026, 00:30 (UTC+01:00)'),
      (DateTime.utc(2026, 1, 1, 1), -210, '31.12.2025, 21:30 (UTC-03:30)'),
      (DateTime.utc(2026, 1, 1, 23), 345, '02.01.2026, 04:45 (UTC+05:45)'),
      (DateTime.utc(2026, 9, 13, 10), 0, '13.09.2026, 10:00 (UTC+00:00)'),
    ]) {
      final reading = _reading(
        '/unused.jpg',
      ).copyWith(capturedAt: sample.$1, timezoneOffsetMinutes: sample.$2);
      expect(EvidenceReportService.readingTimeText(reading, date), sample.$3);
      expect(
        EvidenceReportService.historyTableData([reading], date)[0][0],
        sample.$3,
      );
      expect(
        EvidenceReportService.readingTimeText(
          reading.copyWith(capturedAt: sample.$1.toLocal()),
          date,
        ),
        sample.$3,
      );
    }
  });

  test('historical fields show only differences and preserve empty values', () {
    final original = MeterSnapshot.fromMeter(_meter());
    expect(
      EvidenceReportService.historicalMeterData(original, original),
      isEmpty,
    );
    final current = MeterSnapshot.fromMeter(
      _meter().copyWith(
        label: 'Neuer Name',
        type: MeterType.gas,
        unit: 'mm',
        meterNumber: 'NEU-999',
        location: 'Neuer Marke/Modell',
      ),
    );
    expect(EvidenceReportService.historicalMeterData(original, current), [
      ['Fahrzeugart', _meter().type.label],
      ['Fahrzeugname', 'Alter Fahrzeugname'],
      ['Kennzeichen', 'ALT-777'],
      ['Marke/Modell', 'Nicht angegeben'],
      ['Einheit', 'km'],
    ]);
  });

  test('history table contains only time, reading and progress', () {
    final rows = EvidenceReportService.historyTableData([
      _reading('/unused.jpg'),
    ], DateFormat('dd.MM.yyyy, HH:mm'));
    expect(rows.single, hasLength(3));
    expect(rows.single.join(' '), isNot(contains('Galerieimport')));
  });

  test(
    'page progress uses the older reading and retains Fahrzeugakte wording',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'fahrzeugakte_progress_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final earlier = _reading('/unused.jpg', id: 'earlier').copyWith(
        value: ReadingValue.tryParse('85'),
        capturedAt: DateTime.utc(2026, 9, 12, 10),
      );
      final latest = _reading(
        '/unused.jpg',
      ).copyWith(value: ReadingValue.tryParse('130'));
      final rows = EvidenceReportService.historyTableData([
        latest,
        earlier,
      ], DateFormat('dd.MM.yyyy, HH:mm'));
      expect(rows.map((row) => row[2]), ['45 km', '–']);
      final report =
          await EvidenceReportService(
            exports: MemoryEvidenceExportRepository(),
            documentsDirectoryProvider: () async => temp,
          ).createHistory(
            meter: _meter(),
            readings: [earlier, latest],
            revisions: const {},
            photoMode: EvidencePhotoMode.withoutPhotos,
          );
      expect(report.record.readingIds, [latest.id, earlier.id]);
      if (_auditPdfText) {
        final auditDirectory = await Directory(
          'build/verification',
        ).create(recursive: true);
        await File(
          report.record.filePath,
        ).copy('${auditDirectory.path}/fahrzeugakte-progress.pdf');
        final result = await Process.run('pdftotext', [
          '-layout',
          report.record.filePath,
          '-',
        ]);
        expect(result.exitCode, 0);
        final text = (result.stdout as String).replaceAll(RegExp(r'\s+'), ' ');
        // The arrow is a vector glyph, so PDF text extraction omits it.
        expect(text, contains('85 130 = 45 km Differenz'));
        expect(text, contains('Fahrzeugprotokoll'));
        expect(text, contains('FAHRZEUGAKTE'));
        expect(text, isNot(contains('LESELOG')));
        expect(text, contains('Fahrzeugverlauf'));
        expect(text, isNot(contains('Zähler')));
      }
    },
  );

  for (final kind in EvidenceExportKind.values) {
    for (final mode in EvidencePhotoMode.values) {
      for (final longText in [false, true]) {
        test(
          'exports $kind / $mode with ${longText ? 'long' : 'short'} notes and hidden corrections',
          () async {
            final temp = await Directory.systemTemp.createTemp(
              'evidence_content_',
            );
            addTearDown(() => temp.delete(recursive: true));
            final photo = File('${temp.path}/synthetic.jpg');
            await photo.writeAsBytes(
              img.encodeJpg(img.Image(width: 20, height: 20)),
            );
            final assets = _TestPhotoAssets();
            final exports = MemoryEvidenceExportRepository();
            final service = EvidenceReportService(
              exports: exports,
              documentsDirectoryProvider: () async => temp,
              photoAssets: assets,
            );
            final note = longText ? _longText('NOTIZ') : 'Meine Testnotiz';
            final reading = _reading(photo.path).copyWith(
              note: note,
              capturedAt: longText ? DateTime.utc(2100, 1, 1, 10) : null,
            );
            final readingDate = longText ? '01.01.2100' : '13.09.2026';
            final revision = _revision(longText: longText);
            final before = reading.toJson();
            final report = kind == EvidenceExportKind.singleReading
                ? await service.createSingle(
                    reading: reading,
                    revisions: [revision],
                    photoMode: mode,
                  )
                : await service.createHistory(
                    meter: _meter().copyWith(
                      meterNumber: 'NEU-999',
                      location: 'Neuer Marke/Modell',
                    ),
                    readings: [reading],
                    revisions: {
                      reading.id: [revision],
                    },
                    photoMode: mode,
                  );
            expect(report.bytes.take(4), [0x25, 0x50, 0x44, 0x46]);
            expect(await File(report.record.filePath).exists(), isTrue);
            expect(exports.items, hasLength(1));
            expect(reading.toJson(), before);
            // Hidden OCR/source/revisions still participate in the unchanged
            // manifest; presentation must not delete or normalize them away.
            const integrity = IntegrityService();
            final reportMeter = kind == EvidenceExportKind.singleReading
                ? reading.meter
                : MeterSnapshot.fromMeter(
                    _meter().copyWith(
                      meterNumber: 'NEU-999',
                      location: 'Neuer Marke/Modell',
                    ),
                  );
            expect(
              report.record.manifestSha256,
              await integrity.sha256Text(
                integrity.canonicalJson({
                  'schema': 'meter_reading_evidence_v3',
                  'reportMeter': reportMeter.toJson(),
                  'readings': [integrity.normalizedReadingData(reading)],
                  'revisions': {
                    reading.id: [revision.toJson()],
                  },
                }),
              ),
            );
            expect(
              assets.prepared,
              mode == EvidencePhotoMode.withoutPhotos ? isEmpty : [photo.path],
            );

            if (_auditPdfText) {
              final result = await Process.run('pdftotext', [
                report.record.filePath,
                '-',
              ]);
              expect(result.exitCode, 0, reason: '${result.stderr}');
              final pages = (result.stdout as String)
                  .split('\f')
                  .where((page) => page.trim().isNotEmpty)
                  .toList();
              if (!longText) {
                // Full-size history photos plus historical book data may need
                // a second page; a short single report still fits on one.
                expect(
                  pages,
                  hasLength(
                    kind == EvidenceExportKind.meterHistory &&
                            mode != EvidencePhotoMode.withoutPhotos
                        ? 2
                        : 1,
                  ),
                );
              }
              final text = (result.stdout as String).replaceAll(
                RegExp(r'\s+'),
                ' ',
              );
              expect(text, contains('$readingDate, 12:00 (UTC+02:00)'));
              expect(text, isNot(contains('$readingDate, 10:00 (UTC+02:00)')));
              for (final removed in [
                'OCR-Kandidat',
                'OCR-Konfidenz',
                'RAW-AUDIT-TEXT',
                'Manuell abweichend',
                'Kameraaufnahme',
                'Galerieimport',
                'Gespeichert',
                'Aktuelles Foto hinzugefügt',
                'Korrekturverlauf',
                'Korrektur vom',
                'Vorher:',
                'Neu:',
                'Pruefkorrektur',
                'Dokumentinformationen',
                'Zukunft',
                'zukünftig',
              ]) {
                expect(text, isNot(contains(removed)));
              }
              expect(text, contains('PDF erstellt am'));
              expect(text, contains('ALT-777'));
              expect(text, contains('Fahrzeugangaben bei Erfassung'));
              expect(text, isNot(contains('SHA-256')));
              expect(text, isNot(contains('konnte nicht eingebettet werden')));
              if (kind == EvidenceExportKind.meterHistory) {
                expect(text, contains('Aktuelle Fahrzeugangaben'));
                expect(text, contains('NEU-999'));
                expect(text, contains('Nicht angegeben'));
                expect(
                  '$readingDate, 12:00 (UTC+02:00)'.allMatches(text),
                  hasLength(2),
                );
              } else {
                expect(text, isNot(contains('NEU-999')));
              }
              if (longText) {
                for (final marker in ['NOTIZ']) {
                  expect(text, contains('START$marker'));
                  expect(text, contains('ENDE$marker'));
                  expect('WORT$marker'.allMatches(text), hasLength(800));
                }
                for (final marker in ['GRUND', 'VORHER', 'NACHHER']) {
                  expect(text, isNot(contains('START$marker')));
                  expect(text, isNot(contains('ENDE$marker')));
                }
              } else {
                expect(text, contains(note));
              }
              final audit = await Directory(
                'build/verification',
              ).create(recursive: true);
              await File(report.record.filePath).copy(
                '${audit.path}/fahrzeugakte-${kind.name}-${mode.name}-${longText ? 'long' : 'short'}.pdf',
              );
            }
          },
        );
      }
    }
  }
}

String _longText(String marker) =>
    'START$marker ${List.filled(800, 'WORT${marker}XX ').join()} ENDE$marker';

ReadingRevision _revision({bool longText = false}) => ReadingRevision(
  id: 'revision',
  readingId: 'reading',
  changedAt: DateTime.utc(2026, 9, 13, 12),
  reason: longText ? _longText('GRUND') : 'Pruefkorrektur',
  changes: {
    'Kilometerstand': const ReadingChange(before: '95,0', after: '100,0'),
    'Notiz': ReadingChange(
      before: longText ? _longText('VORHER') : 'Alte Notiz',
      after: longText ? _longText('NACHHER') : 'Meine Testnotiz',
    ),
    'Prüfwert des Fotos (SHA-256)': ReadingChange(
      before: 'c' * 64,
      after: 'a' * 64,
    ),
    'Fotoquelle': const ReadingChange(
      before: 'Kameraaufnahme',
      after: 'Galerieimport',
    ),
    'OCR-Kandidat': const ReadingChange(before: '777,7', after: '100,0'),
  },
);

MeterReading _reading(String path, {String id = 'reading'}) => MeterReading(
  id: id,
  meterId: 'meter',
  meter: MeterSnapshot.fromMeter(_meter()),
  value: ReadingValue.tryParse('100,0')!,
  capturedAt: DateTime.utc(2026, 9, 13, 10),
  timezoneOffsetMinutes: 120,
  storedAt: DateTime.utc(2026, 9, 13, 11),
  updatedAt: DateTime.utc(2026, 9, 13, 12),
  photoAddedAt: DateTime.utc(2026, 9, 13, 12),
  source: ReadingSource.gallery,
  photoPath: path,
  photoSha256: 'a' * 64,
  ocrRawText: 'RAW-AUDIT-TEXT',
  ocrCandidate: '100,0',
  ocrConfidence: 0.92,
  manifestSha256: 'b' * 64,
);

Meter _meter() => Meter(
  id: 'meter',
  label: 'Alter Fahrzeugname',
  type: MeterType.electricity,
  unit: 'km',
  meterNumber: 'ALT-777',
  location: '',
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 9, 13),
);

class _TestPhotoAssets implements EvidencePhotoAssetRepository {
  final prepared = <String>[];

  @override
  Future<String?> prepare({
    required String path,
    required String sha256,
  }) async {
    prepared.add(path);
    return path;
  }

  @override
  Future<void> delete(String sha256) async {}
}
