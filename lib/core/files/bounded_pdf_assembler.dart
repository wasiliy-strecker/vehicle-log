import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:universal_io/io.dart';

import 'document_repository.dart';

/// Works on one bounded output at a time. Source PDFs are opened from disk.
class BoundedPdfAssembler {
  const BoundedPdfAssembler({
    this.maxPages = PdfLimits.reportPages,
    this.maxBytes = PdfLimits.reportBytes,
  });

  final int maxPages;
  final int maxBytes;

  Future<List<File>> assemble({
    required Stream<PdfReportPart> source,
    required Directory staging,
    required Future<Uint8List> Function(int index, int total) cover,
  }) async {
    if (maxPages < 2 || maxBytes < 1) throw ArgumentError('Invalid PDF limits');
    await pdfrxFlutterInitialize();
    final raw = <File>[];
    var serial = 0;
    File nextFile() => File('${staging.path}/part_${serial++}.pdf');

    Future<void> appendPages(PdfDocument output, List<PdfPage> pages) async {
      output.pages = [...output.pages, ...pages];
      if (!await output.assemble()) {
        throw StateError('PDF-Seiten konnten nicht übernommen werden.');
      }
      await output.reloadPages(
        pageNumbersToReload: List.generate(output.pages.length, (i) => i + 1),
      );
    }

    Future<void> saveBounded(PdfDocument document, List<File> into) async {
      final bytes = await document.encodePdf();
      if (bytes.length <= maxBytes && document.pages.length <= maxPages) {
        final file = nextFile();
        await file.writeAsBytes(bytes, flush: true);
        into.add(file);
        return;
      }
      if (document.pages.length <= 1) {
        throw const FormatException(
          'Eine einzelne PDF-Seite ist größer als 50 MB. Das Protokoll wurde nicht gespeichert.',
        );
      }
      final middle = document.pages.length ~/ 2;
      for (final range in [
        document.pages.sublist(0, middle),
        document.pages.sublist(middle),
      ]) {
        final half = await PdfDocument.createNew(
          sourceName: 'Fahrzeugprotokoll',
        );
        try {
          await appendPages(half, range);
          await saveBounded(half, into);
        } finally {
          await half.dispose();
        }
      }
    }

    var current = await PdfDocument.createNew(sourceName: 'Fahrzeugprotokoll');
    var estimatedBytes = 0;
    Future<void> flush() async {
      if (current.pages.isEmpty) return;
      await saveBounded(current, raw);
      await current.dispose();
      current = await PdfDocument.createNew(sourceName: 'Fahrzeugprotokoll');
      estimatedBytes = 0;
    }

    try {
      await for (final part in source) {
        final size = part.bytes?.length ?? await File(part.path!).length();
        final input = part.bytes == null
            ? await PdfDocument.openFile(
                part.path!,
                passwordProvider: () async => null,
              )
            : await PdfDocument.openData(part.bytes!);
        try {
          if (input.isEncrypted || input.pages.isEmpty) {
            throw const FormatException('Ein PDF-Anhang ist nicht lesbar.');
          }
          // Prefer source/entry boundaries when the next block cannot fit.
          if (current.pages.isNotEmpty &&
              (current.pages.length + input.pages.length > maxPages ||
                  estimatedBytes + size > maxBytes)) {
            await flush();
          }
          var offset = 0;
          while (offset < input.pages.length) {
            final count = (maxPages - current.pages.length).clamp(
              1,
              input.pages.length - offset,
            );
            await appendPages(
              current,
              input.pages.sublist(offset, offset + count),
            );
            estimatedBytes += (size * count / input.pages.length).ceil();
            offset += count;
            if (current.pages.length >= maxPages ||
                estimatedBytes >= maxBytes) {
              await flush();
            }
          }
        } finally {
          await input.dispose();
        }
      }
      await flush();
    } finally {
      await current.dispose();
    }
    if (raw.length <= 1) return raw;

    // Cover pages are measured too. If they push a part over either limit,
    // split its contents and regenerate the numbering for the entire set.
    while (true) {
      final finished = <File>[];
      var retry = false;
      for (var index = 0; index < raw.length; index++) {
        final input = await PdfDocument.openFile(raw[index].path);
        final title = await PdfDocument.openData(
          await cover(index + 1, raw.length),
        );
        final output = await PdfDocument.createNew(
          sourceName: 'Fahrzeugprotokoll',
        );
        try {
          await appendPages(output, title.pages);
          await appendPages(output, input.pages);
          final bytes = await output.encodePdf();
          if (output.pages.length <= maxPages && bytes.length <= maxBytes) {
            final file = nextFile();
            await file.writeAsBytes(bytes, flush: true);
            finished.add(file);
          } else {
            if (input.pages.length <= 1) {
              throw const FormatException(
                'Eine PDF-Seite mit Zuordnung überschreitet 50 MB. Das Protokoll wurde nicht gespeichert.',
              );
            }
            final split = <File>[];
            final middle = input.pages.length ~/ 2;
            for (final pages in [
              input.pages.sublist(0, middle),
              input.pages.sublist(middle),
            ]) {
              final half = await PdfDocument.createNew(
                sourceName: 'Fahrzeugprotokoll',
              );
              try {
                await appendPages(half, pages);
                await saveBounded(half, split);
              } finally {
                await half.dispose();
              }
            }
            raw.replaceRange(index, index + 1, split);
            retry = true;
            break;
          }
        } finally {
          await output.dispose();
          await title.dispose();
          await input.dispose();
        }
      }
      if (!retry) return finished;
      for (final file in finished) {
        await file.delete();
      }
    }
  }
}
