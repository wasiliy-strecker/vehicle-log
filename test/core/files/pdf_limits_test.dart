import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/document_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_document.dart';

class _Pdf implements PdfAssemblyService {
  _Pdf(this.pages);
  int pages;
  int calls = 0;
  @override
  Future<int> inspect(String path) async {
    calls++;
    return pages;
  }

  @override
  Future<Uint8List> assemble(List<PdfReportPart> parts) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('page and byte budgets include exact boundaries', () {
    const budget = DocumentImportBudget();
    budget.validate(19, PdfLimits.fileBytes - 1);
    budget.validate(20, PdfLimits.fileBytes);
    expect(() => budget.validate(21, 1), throwsFormatException);
    expect(
      () => budget.validate(1, PdfLimits.fileBytes + 1),
      throwsFormatException,
    );
    final remaining = budget.consume(12, PdfLimits.fileBytes);
    remaining.validate(8, PdfLimits.fileBytes);
    expect(remaining.consume(8, PdfLimits.fileBytes).exhausted, isTrue);
    expect(() => remaining.validate(9, 1), throwsFormatException);
    expect(
      () => const DocumentImportBudget(bytes: 5).validate(1, 6),
      throwsFormatException,
    );
  });
  test('oversize file is rejected before copying or parsing', () async {
    final root = await Directory.systemTemp.createTemp('pdf_limit_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/source.pdf');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(PdfLimits.fileBytes + 1);
    await handle.close();
    final pdf = _Pdf(1);
    final repo = LocalDocumentRepository(
      pdf: pdf,
      directoryProvider: () async => root,
    );
    await expectLater(
      repo.importFile(file.path, 'large.pdf', DocumentSource.imported),
      throwsFormatException,
    );
    expect(pdf.calls, 0);
    expect(Directory('${root.path}/vehicle_documents').existsSync(), isFalse);
  });
  test('page rejection removes copy and preserves source bytes', () async {
    final root = await Directory.systemTemp.createTemp('pdf_limit_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/source.pdf')
      ..writeAsStringSync('%PDF synthetic');
    final pdf = _Pdf(21);
    final repo = LocalDocumentRepository(
      pdf: pdf,
      directoryProvider: () async => root,
    );
    await expectLater(
      repo.importFile(file.path, 'long.pdf', DocumentSource.imported),
      throwsFormatException,
    );
    expect(Directory('${root.path}/vehicle_documents').listSync(), isEmpty);
    expect(file.readAsStringSync(), '%PDF synthetic');
    pdf.pages = 20;
    final imported = await repo.importFile(
      file.path,
      'valid.pdf',
      DocumentSource.imported,
    );
    expect(imported.pageCount, 20);
    expect(await File(imported.path).readAsBytes(), await file.readAsBytes());
    expect(
      imported.sha256,
      await const IntegrityService().sha256Bytes(await file.readAsBytes()),
    );
  });
}
