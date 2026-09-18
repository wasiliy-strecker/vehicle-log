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
  Future<DocumentImportResult> pick({bool multiple = true});
  Future<DocumentImportResult> scan();
  Future<void> delete(String path);
}

abstract interface class DocumentScannerRepository {
  Future<String?> scan();
}

/// Same Android scanner and settings as AI Contract Manager.
class AndroidDocumentScannerRepository implements DocumentScannerRepository {
  const AndroidDocumentScannerRepository();

  @override
  Future<String?> scan() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const FormatException(
        'Dokument scannen ist auf Android verfügbar. Du kannst eine vorhandene PDF auswählen.',
      );
    }
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg, DocumentFormat.pdf},
        pageLimit: 20,
        mode: ScannerMode.full,
        isGalleryImport: false,
      ),
    );
    try {
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
        'Der Dokumentscanner konnte nicht geöffnet werden. Prüfe Google Play Services und die Internetverbindung beim ersten Start. Deine Eingaben bleiben erhalten.',
      );
    } finally {
      await scanner.close();
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
  Future<DocumentImportResult> pick({bool multiple = true}) async {
    if (kIsWeb) {
      throw const FormatException(
        'PDF-Dateiabläufe bitte in der Android-App testen.',
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
        documents.add(
          await importFile(file.path!, file.name, DocumentSource.imported),
        );
      } catch (error) {
        failures.add('${file.name}: $error');
      }
    }
    return DocumentImportResult(documents: documents, failures: failures);
  }

  @override
  Future<DocumentImportResult> scan() async {
    final path = await scanner.scan();
    if (path == null) return const DocumentImportResult();
    final now = DateTime.now();
    final name = 'Scan_${now.toIso8601String().replaceAll(':', '-')}.pdf';
    return DocumentImportResult(
      documents: [await importFile(path, name, DocumentSource.scanned)],
    );
  }

  Future<ReadingDocument> importFile(
    String sourcePath,
    String name,
    DocumentSource source,
  ) async {
    final sourceFile = File(sourcePath);
    if (!name.toLowerCase().endsWith('.pdf') || !await sourceFile.exists()) {
      throw const FormatException('Bitte eine lesbare PDF-Datei auswählen.');
    }
    final id = newLocalId('document');
    final directory = Directory(
      p.join((await directoryProvider()).path, 'vehicle_documents'),
    );
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, '$id.pdf'));
    try {
      await sourceFile.copy(target.path);
      final pageCount = await pdf.inspect(target.path);
      return ReadingDocument(
        id: id,
        fileName: p.basename(name),
        path: target.path,
        sha256: await const IntegrityService().sha256Bytes(
          await target.readAsBytes(),
        ),
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
