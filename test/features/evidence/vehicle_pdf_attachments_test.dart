import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:fahrzeugakte/core/files/document_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Flutter 3.41's test runner does not expose hook assets to PDFium's worker.
  // Use the library already prepared by flutter test, without any SDK changes.
  if (Platform.isLinux) {
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/linux/libpdfium.so',
    ).absolute.path;
  }
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vehicle_pdf_audit_');
    Pdfrx.cacheDirectoryPath = root.path;
  });
  tearDown(() async => root.delete(recursive: true));

  Future<File> source(
    String name,
    List<String> pages, {
    bool landscape = false,
  }) async {
    final doc = pw.Document();
    for (final text in pages) {
      doc.addPage(
        pw.Page(
          pageFormat: landscape
              ? pdf.PdfPageFormat.a4.landscape
              : pdf.PdfPageFormat.a4,
          build: (_) => pw.Text(text),
        ),
      );
    }
    return File('${root.path}/$name.pdf')..writeAsBytesSync(await doc.save());
  }

  test(
    'PDF multi-selection keeps valid files and reports each rejected file',
    () async {
      const picker = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(picker, null),
      );
      final a = await source('selected_a', ['SELECTED_A']);
      final b = await source('selected_b', ['SELECTED_B']);
      final broken = File('${root.path}/broken.pdf')
        ..writeAsStringSync('broken');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
            expect(call.method, 'custom');
            expect(call.arguments['allowedExtensions'], ['pdf']);
            expect(call.arguments['withData'], isFalse);
            expect(call.arguments['allowMultipleSelection'], isTrue);
            return [
              {'name': 'Beleg A.pdf', 'path': a.path, 'size': a.lengthSync()},
              {
                'name': 'kaputt.pdf',
                'path': broken.path,
                'size': broken.lengthSync(),
              },
              {'name': 'Beleg B.PDF', 'path': b.path, 'size': b.lengthSync()},
              {'name': 'nicht-lokal.pdf', 'path': null, 'size': 1},
            ];
          });
      final repository = LocalDocumentRepository(
        directoryProvider: () async => root,
      );
      final result = await repository.pick();
      expect(result.documents.map((d) => d.fileName), [
        'Beleg A.pdf',
        'Beleg B.PDF',
      ]);
      expect(result.failures, hasLength(2));
      expect(result.failures[0], contains('kaputt.pdf'));
      expect(result.failures[1], contains('nicht-lokal.pdf'));
      expect(
        Directory('${root.path}/vehicle_documents').listSync(),
        hasLength(2),
      );
      expect(
        await File(result.documents.first.path).readAsBytes(),
        await a.readAsBytes(),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
            expect(call.arguments['allowMultipleSelection'], isFalse);
            return null;
          });
      final cancelled = await repository.pick(multiple: false);
      expect(cancelled.documents, isEmpty);
      expect(cancelled.failures, isEmpty);
      expect(
        Directory('${root.path}/vehicle_documents').listSync(),
        hasLength(2),
      );
    },
  );

  test(
    'original PDF pages remain searchable, correctly ordered and in landscape',
    () async {
      final repo = LocalDocumentRepository(directoryProvider: () async => root);
      final original = await source('invoice', [
        'INVOICE_PAGE_ONE',
        'INVOICE_PAGE_TWO',
      ], landscape: true);
      final originalBytes = await original.readAsBytes();
      final invoice = await repo.importFile(
        original.path,
        'Rechnung.pdf',
        DocumentSource.imported,
      );
      final reportFile = await source('report', ['INSPECTION_REPORT']);
      final report = await repo.importFile(
        reportFile.path,
        'Pruefbericht.pdf',
        DocumentSource.scanned,
      );
      final vehicle = sampleBook(
        label: 'Testauto',
      ).copyWith(vin: 'SYNTHETIC000000001', firstRegistration: '03.2020');
      final reading = sampleReading(book: vehicle, source: ReadingSource.manual)
          .copyWith(
            workshop: 'Testwerkstatt',
            costCents: 12345,
            documents: [invoice, report],
          );
      final exports = MemoryEvidenceExportRepository();
      final service = EvidenceReportService(
        exports: exports,
        documentsDirectoryProvider: () async => root,
      );
      final single = await service.createSingle(
        reading: reading,
        revisions: [],
      );
      final result = await PdfDocument.openData(
        single.bytes,
        sourceName: 'single',
      );
      try {
        final texts = <String>[];
        for (final page in result.pages) {
          texts.add((await page.loadText())!.fullText);
        }
        final one = texts.indexWhere((t) => t.contains('INVOICE_PAGE_ONE'));
        final two = texts.indexWhere((t) => t.contains('INVOICE_PAGE_TWO'));
        final inspection = texts.indexWhere(
          (t) => t.contains('INSPECTION_REPORT'),
        );
        expect(one, greaterThan(0), reason: texts.toString());
        expect(two, one + 1);
        expect(inspection, greaterThan(two));
        expect(result.pages[one].width, greaterThan(result.pages[one].height));
        expect(texts.join(), contains('Testwerkstatt'));
        expect(texts.join(), contains('123,45'));
        expect(texts.join(), contains('SYNTHETIC000000001'));
      } finally {
        await result.dispose();
      }
      expect(await File(invoice.path).readAsBytes(), originalBytes);

      final compact = await service.createSingle(
        reading: reading,
        revisions: [],
        photoMode: EvidencePhotoMode.withoutPhotos,
      );
      final compactDoc = await PdfDocument.openData(
        compact.bytes,
        sourceName: 'compact',
      );
      try {
        final texts = <String>[];
        for (final page in compactDoc.pages) {
          texts.add((await page.loadText())!.fullText);
        }
        expect(texts.join(), contains('Rechnung.pdf'));
        expect(texts.join(), isNot(contains('INVOICE_PAGE_ONE')));
      } finally {
        await compactDoc.dispose();
      }

      final older = sampleReading(
        id: 'older',
        book: vehicle,
        source: ReadingSource.manual,
      ).copyWith(capturedAt: DateTime.utc(2025), documents: [report]);
      final history = await service.createHistory(
        meter: vehicle.copyWith(vin: 'CURRENTVIN00000002'),
        readings: [
          older,
          reading.copyWith(documents: [invoice]),
        ],
        revisions: {},
      );
      final historyDoc = await PdfDocument.openData(
        history.bytes,
        sourceName: 'history',
      );
      try {
        final texts = <String>[];
        for (final page in historyDoc.pages) {
          texts.add((await page.loadText())!.fullText);
        }
        final invoiceIndex = texts.indexWhere(
          (t) => t.contains('INVOICE_PAGE_ONE'),
        );
        final olderIndex = texts.indexWhere(
          (t) => t.contains('Eintrag 1') && t.contains('Fahrzeugprotokoll'),
        );
        final reportIndex = texts.indexWhere(
          (t) => t.contains('INSPECTION_REPORT'),
        );
        expect(invoiceIndex, greaterThan(0), reason: texts.toString());
        expect(olderIndex, greaterThan(invoiceIndex));
        expect(reportIndex, greaterThan(olderIndex));
        expect(texts.join(), contains('SYNTHETIC000000001'));
        expect(texts.join(), contains('CURRENTVIN00000002'));
      } finally {
        await historyDoc.dispose();
      }
    },
  );

  test(
    'password-protected PDFs are rejected without retaining a copy',
    () async {
      final repo = LocalDocumentRepository(directoryProvider: () async => root);
      await expectLater(
        repo.importFile(
          'test/fixtures/documents/password-protected.pdf',
          'protected.pdf',
          DocumentSource.imported,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Passwortschutz'),
          ),
        ),
      );
      expect(
        await Directory('${root.path}/vehicle_documents').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'edits export the current PDF order and keep older reports unchanged',
    () async {
      final repository = LocalDocumentRepository(
        directoryProvider: () async => root,
      );
      Future<ReadingDocument> import(String name) async {
        final file = await source(name, ['ATTACHMENT_$name']);
        return repository.importFile(
          file.path,
          '$name.pdf',
          DocumentSource.imported,
        );
      }

      final a = await import('AAA');
      final b = await import('BBB');
      final c = await import('CCC');
      final original = sampleReading(
        source: ReadingSource.manual,
      ).copyWith(documents: [a, b]);
      final readings = MemoryReadingRepository()..items[original.id] = original;
      final exports = MemoryEvidenceExportRepository();
      final reports = EvidenceReportService(
        exports: exports,
        documentsDirectoryProvider: () async => root,
      );
      final oldReport = await reports.createSingle(
        reading: original,
        revisions: [],
      );
      final editing = MeterReadingService(
        meters: MemoryMeterRepository(),
        readings: readings,
        exports: exports,
        photos: const UnsupportedMeterPhotoCaptureRepository(),
        reminders: NoopMeterReminderRepository(),
      );
      final updated = await editing.update(
        existing: original,
        value: original.value,
        capturedAt: original.capturedAt,
        note: 'Replaced, removed and reordered',
        documents: [c, b],
      );
      expect(File(a.path).existsSync(), isFalse);
      expect(File(b.path).existsSync(), isTrue);
      expect(updated.documentHistory, isEmpty);
      expect(await readings.loadRevisions(updated.id), isEmpty);
      final report = await reports.createSingle(
        reading: updated,
        revisions: [],
      );
      final document = await PdfDocument.openData(
        report.bytes,
        sourceName: 'edited',
      );
      try {
        final text = (await Future.wait(
          document.pages.map((page) async => (await page.loadText())!.fullText),
        )).join('\n');
        expect(text, isNot(contains('ATTACHMENT_AAA')));
        expect(text, contains('ATTACHMENT_CCC'));
        expect(
          text.indexOf('ATTACHMENT_CCC'),
          lessThan(text.indexOf('ATTACHMENT_BBB')),
        );
      } finally {
        await document.dispose();
      }
      expect(
        await File(oldReport.record.filePath).readAsBytes(),
        oldReport.bytes,
      );
      expect(await exports.loadAll(), hasLength(2));
    },
  );

  test(
    'tampered PDFs and incorrect page counts never create a partial export',
    () async {
      final repository = LocalDocumentRepository(
        directoryProvider: () async => root,
      );
      final file = await source(
        'twenty_pages',
        List.generate(20, (i) => 'PAGE_${i + 1}'),
      );
      final attachment = await repository.importFile(
        file.path,
        'Rechnung.PDF',
        DocumentSource.scanned,
      );
      expect(attachment.pageCount, 20);
      final exports = MemoryEvidenceExportRepository();
      final reports = EvidenceReportService(
        exports: exports,
        documentsDirectoryProvider: () async => root,
      );
      final wrongCount = ReadingDocument.fromJson({
        ...attachment.toJson(),
        'pageCount': 21,
      });
      await expectLater(
        reports.createSingle(
          reading: sampleReading(
            source: ReadingSource.manual,
          ).copyWith(documents: [wrongCount]),
          revisions: [],
        ),
        throwsStateError,
      );
      await File(
        attachment.path,
      ).writeAsString('changed', mode: FileMode.append);
      await expectLater(
        reports.createSingle(
          reading: sampleReading(
            source: ReadingSource.manual,
          ).copyWith(documents: [attachment]),
          revisions: [],
        ),
        throwsStateError,
      );
      expect(await exports.loadAll(), isEmpty);
      expect(Directory('${root.path}/evidence_reports').existsSync(), isFalse);
    },
  );

  test(
    'broken imports clean their copy and missing attachments prevent full exports',
    () async {
      final repo = LocalDocumentRepository(directoryProvider: () async => root);
      final broken = File('${root.path}/broken.pdf')
        ..writeAsStringSync('not a PDF');
      await expectLater(
        repo.importFile(broken.path, 'broken.pdf', DocumentSource.imported),
        throwsFormatException,
      );
      expect(
        await Directory('${root.path}/vehicle_documents').list().toList(),
        isEmpty,
      );
      final file = await source('valid', ['VALID']);
      final doc = await repo.importFile(
        file.path,
        'valid.pdf',
        DocumentSource.imported,
      );
      final reading = sampleReading(
        source: ReadingSource.manual,
      ).copyWith(documents: [doc]);
      await File(doc.path).delete();
      final exports = MemoryEvidenceExportRepository();
      final service = EvidenceReportService(
        exports: exports,
        documentsDirectoryProvider: () async => root,
      );
      await expectLater(
        service.createSingle(reading: reading, revisions: []),
        throwsStateError,
      );
      expect(await exports.loadAll(), isEmpty);
      final compact = await service.createSingle(
        reading: reading,
        revisions: [],
        photoMode: EvidencePhotoMode.withoutPhotos,
      );
      expect(compact.bytes, isNotEmpty);
    },
  );
}
