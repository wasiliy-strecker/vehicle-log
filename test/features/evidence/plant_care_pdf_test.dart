import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final measured in [false, true]) {
    test(
      'PDF shows the current custom activity while retaining revision metadata, height=$measured',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'custom_activity_pdf_',
        );
        addTearDown(() => temp.delete(recursive: true));
        const label =
            'Blätter besprüht und anschließend vorsichtig von Staub befreit, neue Triebe kontrolliert';
        final reading = sampleReading(source: ReadingSource.manual).copyWith(
          activity: CareActivity.custom,
          customActivityLabel: label,
          hasMeasurement: measured,
        );
        final revision = ReadingRevision(
          id: 'custom',
          readingId: reading.id,
          changedAt: reading.updatedAt,
          reason: '',
          changes: const {
            'Aktivität': ReadingChange(before: 'Erste Blüte', after: label),
          },
        );
        final service = EvidenceReportService(
          exports: MemoryEvidenceExportRepository(),
          documentsDirectoryProvider: () async => temp,
        );
        for (final history in [false, true]) {
          final report = history
              ? await service.createHistory(
                  meter: sampleBook(),
                  readings: [reading],
                  revisions: {
                    reading.id: [revision],
                  },
                  photoMode: EvidencePhotoMode.withoutPhotos,
                )
              : await service.createSingle(
                  reading: reading,
                  revisions: [revision],
                  photoMode: EvidencePhotoMode.withoutPhotos,
                );
          expect(report.bytes.length, greaterThan(1000));
          if (const bool.fromEnvironment('PDF_TEXT_AUDIT')) {
            final result = await Process.run('pdftotext', [
              '-raw',
              report.record.filePath,
              '-',
            ]);
            expect(result.exitCode, 0);
            final text = (result.stdout as String).replaceAll(
              RegExp(r'\s+'),
              ' ',
            );
            expect(text, contains(label));
            if (!history) expect(text, contains('Aktivität'));
            expect(text, isNot(contains('Erste Blüte')));
            if (!measured) expect(text, isNot(contains('85 km')));
          }
        }
      },
    );
  }
  test(
    'PDF preserves every care action and omits absent height values',
    () async {
      final temp = await Directory.systemTemp.createTemp('plant_care_pdf_');
      addTearDown(() => temp.delete(recursive: true));
      final plant = sampleBook(label: 'Familienauto');
      final readings = [
        for (final activity in CareActivity.presets)
          sampleReading(
            id: activity.name,
            book: plant,
            value: '987654',
            source: ReadingSource.manual,
          ).copyWith(
            activity: activity,
            hasMeasurement: false,
            note: 'Notiz ${activity.label}',
            capturedAt: DateTime.utc(2026, 9, 16, activity.index),
          ),
      ];
      final service = EvidenceReportService(
        exports: MemoryEvidenceExportRepository(),
        documentsDirectoryProvider: () async => temp,
      );
      for (final history in [false, true]) {
        final report = history
            ? await service.createHistory(
                meter: plant,
                readings: readings,
                revisions: const {},
                photoMode: EvidencePhotoMode.withoutPhotos,
              )
            : await service.createSingle(
                reading: readings.first,
                revisions: const [],
                photoMode: EvidencePhotoMode.withoutPhotos,
              );
        expect(report.bytes.length, greaterThan(1000));
        if (const bool.fromEnvironment('PDF_TEXT_AUDIT')) {
          final result = await Process.run('pdftotext', [
            report.record.filePath,
            '-',
          ]);
          expect(result.exitCode, 0);
          final text = result.stdout as String;
          for (final activity
              in history ? CareActivity.presets : [CareActivity.watering]) {
            expect(text, contains(activity.label));
          }
          expect(text, isNot(contains('987654')));
          expect(text, contains('Ohne Kilometerangabe'));
        }
      }
    },
  );
}
