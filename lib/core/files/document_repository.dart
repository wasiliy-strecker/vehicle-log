import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:universal_io/io.dart';

import '../../features/meters/domain/reading_document.dart';
import '../integrity/integrity_service.dart';
import 'pdf_limits.dart';
export 'pdf_limits.dart';
import '../utils/id_generator.dart';

class DocumentImportResult {
  const DocumentImportResult({
    this.documents = const [],
    this.failures = const [],
  });
  final List<ReadingDocument> documents;
  final List<String> failures;
}

abstract interface class DocumentRepository {
  Future<DocumentImportResult> pick({
    bool multiple = true,
    DocumentImportBudget budget = const DocumentImportBudget(),
  });
  Future<DocumentImportResult> scan({
    DocumentImportBudget budget = const DocumentImportBudget(),
  });
  Future<void> delete(String path);
}

abstract interface class DocumentScannerRepository {
  Future<String?> scan({int pageLimit = PdfLimits.entryPages});
}

/// Same Android scanner and settings as AI Contract Manager.
class AndroidDocumentScannerRepository implements DocumentScannerRepository {
  const AndroidDocumentScannerRepository();
  static const _lifecycle = MethodChannel(
    'com.appfactory.vehicle_log/document_scan_lifecycle',
  );

  @override
  Future<String?> scan({int pageLimit = PdfLimits.entryPages}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const FormatException(
        'Dokument scannen ist auf Android verfügbar. Du kannst eine vorhandene PDF auswählen.',
      );
    }
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg, DocumentFormat.pdf},
        pageLimit: pageLimit.clamp(1, PdfLimits.entryPages),
        mode: ScannerMode.full,
        isGalleryImport: false,
      ),
    );
    var ownsScan = false;
    try {
      await _lifecycle.invokeMethod<void>('begin');
      ownsScan = true;
      final result = await scanner.scanDocument();
      final uri = result.pdf?.uri;
      if (uri == null || uri.trim().isEmpty) {
        throw const FormatException(
          'Der Scanner hat keine PDF geliefert. Bitte den Scan wiederholen.',
        );
      }
      return uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
    } on PlatformException catch (error) {
      if ((error.message ?? '').toLowerCase().contains('cancel')) return null;
      throw const FormatException(
        'Der Dokumentscanner ist nicht verfügbar. Er benötigt Google Play Services und mindestens 1,7 GB Arbeitsspeicher. Prüfe auch die Internetverbindung beim ersten Start. Du kannst stattdessen eine PDF auswählen. Deine Eingaben bleiben erhalten.',
      );
    } finally {
      if (ownsScan) {
        try {
          await scanner.close();
        } on PlatformException {
          // Cleanup must not discard a completed scan or replace its error.
        } finally {
          try {
            await _lifecycle.invokeMethod<void>('finish');
          } on PlatformException {
            // The native activity may already have been detached.
          }
        }
      }
    }
  }
}

abstract interface class PdfAssemblyService {
  Future<int> inspect(String path);
  Future<Uint8List> assemble(List<PdfReportPart> parts);
}

class PdfReportPart {
  const PdfReportPart.bytes(this.bytes) : path = null;
  const PdfReportPart.file(this.path) : bytes = null;
  final Uint8List? bytes;
  final String? path;
}

class LocalPdfAssemblyService implements PdfAssemblyService {
  const LocalPdfAssemblyService();

  @override
  Future<int> inspect(String path) async {
    await pdfrxFlutterInitialize();
    final PdfDocument document;
    try {
      document = await PdfDocument.openFile(
        path,
        passwordProvider: () async => null,
      );
    } on PdfPasswordException {
      throw const FormatException(
        'Bitte eine PDF ohne Passwortschutz auswählen.',
      );
    } on PdfException {
      throw const FormatException('Die PDF ist beschädigt oder nicht lesbar.');
    }
    try {
      if (document.isEncrypted) {
        throw const FormatException(
          'Bitte eine PDF ohne Passwortschutz auswählen.',
        );
      }
      if (document.pages.isEmpty) {
        throw const FormatException('Die PDF enthält keine Seiten.');
      }
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  @override
  Future<Uint8List> assemble(List<PdfReportPart> parts) async {
    await pdfrxFlutterInitialize();
    final output = await PdfDocument.createNew(sourceName: 'Fahrzeugakte.pdf');
    try {
      for (final part in parts) {
        final input = part.bytes == null
            ? await PdfDocument.openFile(
                part.path!,
                passwordProvider: () async => null,
              )
            : await PdfDocument.openData(part.bytes!, sourceName: 'Protokoll');
        try {
          if (input.isEncrypted || input.pages.isEmpty) {
            throw const FormatException(
              'Ein PDF-Anhang konnte nicht vollständig übernommen werden.',
            );
          }
          output.pages = [...output.pages, ...input.pages];
          // Copy the pages before releasing the source, keeping memory bounded.
          if (!await output.assemble()) {
            throw StateError('PDF-Seiten konnten nicht zusammengefügt werden.');
          }
          // pdfrx 2.4 keeps source-page wrappers after assemble. Rebind them
          // to the output before closing the source or appending another file.
          await output.reloadPages(
            pageNumbersToReload: List.generate(
              output.pages.length,
              (index) => index + 1,
            ),
          );
        } finally {
          await input.dispose();
        }
      }
      return await output.encodePdf();
    } finally {
      await output.dispose();
    }
  }
}

class LocalDocumentRepository implements DocumentRepository {
  LocalDocumentRepository({
    this.scanner = const AndroidDocumentScannerRepository(),
    this.pdf = const LocalPdfAssemblyService(),
    Future<Directory> Function()? directoryProvider,
  }) : directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  final DocumentScannerRepository scanner;
  final PdfAssemblyService pdf;
  final Future<Directory> Function() directoryProvider;

  @override
  Future<DocumentImportResult> pick({
    bool multiple = true,
    DocumentImportBudget budget = const DocumentImportBudget(),
  }) async {
    if (kIsWeb) {
      throw const FormatException(
        'PDF-Dateiabläufe bitte in der Android-App testen.',
      );
    }
    if (budget.exhausted) {
      throw const FormatException(
        'Das PDF-Limit ist erreicht. Entferne oder ersetze einen Anhang.',
      );
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: multiple,
      withData: false,
    );
    if (result == null) return const DocumentImportResult();
    final documents = <ReadingDocument>[];
    final failures = <String>[];
    for (final file in result.files) {
      try {
        if (file.path == null) {
          throw const FormatException('Datei nicht lesbar');
        }
        final imported = await importFile(
          file.path!,
          file.name,
          DocumentSource.imported,
          budget: budget,
        );
        documents.add(imported);
        budget = budget.consume(imported.pageCount, imported.sizeBytes);
      } catch (error) {
        final message = error is FormatException
            ? error.message
            : 'Die Datei konnte nicht als PDF gelesen werden.';
        failures.add('${file.name}: $message');
      }
    }
    return DocumentImportResult(documents: documents, failures: failures);
  }

  @override
  Future<DocumentImportResult> scan({
    DocumentImportBudget budget = const DocumentImportBudget(),
  }) async {
    if (budget.exhausted) {
      throw const FormatException(
        'Das PDF-Limit ist erreicht. Entferne oder ersetze einen Anhang.',
      );
    }
    final path = await scanner.scan(
      pageLimit: budget.pages.clamp(1, PdfLimits.entryPages),
    );
    if (path == null) return const DocumentImportResult();
    final now = DateTime.now();
    final name = 'Scan_${now.toIso8601String().replaceAll(':', '-')}.pdf';
    return DocumentImportResult(
      documents: [
        await importFile(path, name, DocumentSource.scanned, budget: budget),
      ],
    );
  }

  Future<ReadingDocument> importFile(
    String sourcePath,
    String name,
    DocumentSource source, {
    DocumentImportBudget budget = const DocumentImportBudget(),
  }) async {
    final sourceFile = File(sourcePath);
    if (!name.toLowerCase().endsWith('.pdf') || !await sourceFile.exists()) {
      throw const FormatException('Bitte eine lesbare PDF-Datei auswählen.');
    }
    budget.validate(1, await sourceFile.length());
    final id = newLocalId('document');
    final directory = Directory(
      p.join((await directoryProvider()).path, 'vehicle_documents'),
    );
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, '$id.pdf'));
    try {
      final sink = target.openWrite();
      var copied = 0;
      try {
        await sink.addStream(
          sourceFile.openRead().map((chunk) {
            copied += chunk.length;
            if (copied > budget.fileBytes) {
              throw const FormatException(
                'Die PDF überschreitet die erlaubte Dateigröße.',
              );
            }
            return chunk;
          }),
        );
      } finally {
        await sink.close();
      }
      final pageCount = await pdf.inspect(target.path);
      budget.validate(pageCount, await target.length());
      return ReadingDocument(
        id: id,
        fileName: p.basename(name),
        path: target.path,
        sha256: await const IntegrityService().sha256Stream(target.openRead()),
        pageCount: pageCount,
        sizeBytes: await target.length(),
        source: source,
        addedAt: DateTime.now().toUtc(),
      );
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
