import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:fahrzeugakte/core/files/bounded_pdf_assembler.dart';
import 'package:fahrzeugakte/core/files/document_repository.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/reading_fixtures.dart';
import '../../support/fakes.dart';

Future<Uint8List> pdfPages(
  int count, {
  int offset = 0,
  bool cover = false,
}) async {
  final pdf = pw.Document();
  for (var i = 0; i < count; i++) {
    pdf.addPage(
      pw.Page(
        build: (_) => pw.Text(
          cover
              ? 'PART $offset'
              : 'CONTENT_${(offset + i).toString().padLeft(4, '0')}_END',
        ),
      ),
    );
  }
  return pdf.save();
}

Future<String> pdfText(File file) async {
  final doc = await PdfDocument.openFile(file.path);
  try {
    final text = StringBuffer();
    for (final page in doc.pages) {
      text.writeln((await page.loadText())?.fullText ?? '');
    }
    return text.toString();
  } finally {
    await doc.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final pages in [99, 100, 101, 205]) {
    test(
      '$pages pages split losslessly within final page and byte limits',
      () async {
        final root = await Directory.systemTemp.createTemp('pdf_parts_');
        addTearDown(() => root.delete(recursive: true));
        final source = File('${root.path}/input.pdf')
          ..writeAsBytesSync(await pdfPages(pages));
        final before = source.readAsBytesSync();
        final parts = await const BoundedPdfAssembler().assemble(
          source: Stream.value(PdfReportPart.file(source.path)),
          staging: root,
          cover: (i, n) => pdfPages(1, offset: i, cover: true),
        );
        expect(parts.length, pages <= 100 ? 1 : greaterThan(1));
        final content = StringBuffer();
        for (final part in parts) {
          final doc = await PdfDocument.openFile(part.path);
          expect(doc.pages.length, lessThanOrEqualTo(100));
          await doc.dispose();
          expect(part.lengthSync(), lessThanOrEqualTo(50000000));
          content.write(await pdfText(part));
        }
        final markers = RegExp(
          r'CONTENT_\d{4}_END',
        ).allMatches(content.toString()).map((m) => m[0]).toList();
        expect(markers, [
          for (var i = 0; i < pages; i++)
            'CONTENT_${i.toString().padLeft(4, '0')}_END',
        ]);
        expect(source.readAsBytesSync(), before);
      },
    );
  }
  test(
    'byte budget triggers splitting and rejects an oversized single page',
    () async {
      final root = await Directory.systemTemp.createTemp('pdf_byte_parts_');
      addTearDown(() => root.delete(recursive: true));
      final inputs = [
        for (var i = 0; i < 12; i++)
          PdfReportPart.bytes(await pdfPages(1, offset: i)),
      ];
      final parts = await const BoundedPdfAssembler(maxBytes: 6000).assemble(
        source: Stream.fromIterable(inputs),
        staging: root,
        cover: (i, n) => pdfPages(1, offset: i, cover: true),
      );
      expect(parts.length, greaterThan(1));
      for (final file in parts) {
        expect(file.lengthSync(), lessThanOrEqualTo(6000));
      }
      await expectLater(
        const BoundedPdfAssembler(maxBytes: 100).assemble(
          source: Stream.value(inputs.first),
          staging: root,
          cover: (i, n) => pdfPages(1, cover: true),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'multipart save failure rolls back every report and removes new files',
    () async {
      final root = await Directory.systemTemp.createTemp('pdf_atomic_batch_');
      final db = AppDatabase.memory();
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
      final exports = DriftEvidenceExportRepository(db);
      await db.customStatement(
        "CREATE TRIGGER fail_second BEFORE INSERT ON evidence_export_records WHEN (SELECT COUNT(*) FROM evidence_export_records) >= 1 BEGIN SELECT RAISE(ABORT, 'synthetic second part failure'); END",
      );
      final meter = sampleBook();
      final source = File('${root.path}/original.pdf')
        ..writeAsBytesSync(await pdfPages(8));
      final repo = LocalDocumentRepository(directoryProvider: () async => root);
      final document = await repo.importFile(
        source.path,
        'original.pdf',
        DocumentSource.imported,
      );
      final reading = sampleReading(
        book: meter,
        source: ReadingSource.manual,
      ).copyWith(documents: [document]);
      final service = EvidenceReportService(
        exports: exports,
        reportAssembler: const BoundedPdfAssembler(maxPages: 4),
        documentsDirectoryProvider: () async => root,
      );
      await expectLater(
        service.createHistory(
          meter: meter,
          readings: [reading],
          revisions: const {},
        ),
        throwsA(isA<Exception>()),
      );
      expect(await exports.loadAll(), isEmpty);
      expect(Directory('${root.path}/evidence_reports').listSync(), isEmpty);
      expect(await File(document.path).exists(), isTrue);
    },
  );
  test(
    'multipart records retain names and PDF contents after encrypted restore',
    () async {
      final root = await Directory.systemTemp.createTemp('pdf_batch_records_');
      addTearDown(() => root.delete(recursive: true));
      final meter = sampleBook();
      final source = File('${root.path}/original.pdf')
        ..writeAsBytesSync(await pdfPages(8));
      final repo = LocalDocumentRepository(directoryProvider: () async => root);
      final document = await repo.importFile(
        source.path,
        'original.pdf',
        DocumentSource.imported,
      );
      final reading = sampleReading(
        book: meter,
        source: ReadingSource.manual,
      ).copyWith(documents: [document]);
      final exports = MemoryEvidenceExportRepository();
      final service = EvidenceReportService(
        exports: exports,
        reportAssembler: const BoundedPdfAssembler(maxPages: 4),
        documentsDirectoryProvider: () async => root,
      );
      final result = await service.createHistory(
        meter: meter,
        readings: [reading],
        revisions: const {},
      );
      expect(result.records.length, greaterThan(1));
      expect(await exports.loadAll(), hasLength(result.records.length));
      final backupService = EncryptedBackupService(
        meters: MemoryMeterRepository()..items[meter.id] = meter,
        readings: MemoryReadingRepository()..items[reading.id] = reading,
        exports: exports,
        reminders: NoopMeterReminderRepository(),
        kdfIterations: 1000,
        temporaryDirectoryProvider: () async => root,
        documentsDirectoryProvider: () async => root,
      );
      final backup = await backupService.create('synthetic-test-password');
      final restoredExports = MemoryEvidenceExportRepository();
      final restoredRoot = await Directory('${root.path}/restored').create();
      await EncryptedBackupService(
        meters: MemoryMeterRepository(),
        readings: MemoryReadingRepository(),
        exports: restoredExports,
        reminders: NoopMeterReminderRepository(),
        kdfIterations: 1000,
        temporaryDirectoryProvider: () async => restoredRoot,
        documentsDirectoryProvider: () async => restoredRoot,
      ).restore(backup.path, 'synthetic-test-password');
      expect(await restoredExports.loadAll(), hasLength(result.records.length));
      for (final (index, record) in result.records.indexed) {
        final reloaded = EvidenceExportRecord.fromJson(record.toJson());
        expect(
          reloaded.partLabel,
          'Teil ${index + 1} von ${result.records.length}',
        );
        expect(
          await pdfText(File(record.filePath)),
          contains('Teil ${index + 1} von ${result.records.length}'),
        );
        final restored = (await restoredExports.loadAll()).singleWhere(
          (item) => item.id == record.id,
        );
        expect(restored.partLabel, reloaded.partLabel);
        expect(restored.pdfSha256, record.pdfSha256);
        expect(
          File(restored.filePath).readAsBytesSync(),
          File(record.filePath).readAsBytesSync(),
        );
      }
    },
  );
}
