/// Decimal MB, matching the limits displayed in the app.
abstract final class PdfLimits {
  static const entryPages = 20;
  static const fileBytes = 25000000;
  static const entryBytes = 50000000;
  static const reportPages = 100;
  static const reportBytes = 50000000;
}

class DocumentImportBudget {
  const DocumentImportBudget({
    this.pages = PdfLimits.entryPages,
    this.bytes = PdfLimits.entryBytes,
  });

  final int pages;
  final int bytes;
  int get fileBytes =>
      bytes < PdfLimits.fileBytes ? bytes : PdfLimits.fileBytes;
  bool get exhausted => pages <= 0 || bytes <= 0;

  void validate(int pageCount, int sizeBytes) {
    if (pageCount < 1 || sizeBytes < 1) {
      throw const FormatException('Die PDF ist leer oder nicht lesbar.');
    }
    if (sizeBytes > PdfLimits.fileBytes) {
      throw const FormatException('Eine PDF darf höchstens 25 MB groß sein.');
    }
    if (sizeBytes > bytes) {
      throw const FormatException(
        'PDF-Anhänge dürfen zusammen höchstens 50 MB groß sein.',
      );
    }
    if (pageCount > pages || pageCount > PdfLimits.entryPages) {
      throw FormatException(
        'Pro Eintrag sind insgesamt 20 PDF-Seiten möglich. Noch verfügbar: ${pages.clamp(0, PdfLimits.entryPages)}.',
      );
    }
  }

  DocumentImportBudget consume(int pageCount, int sizeBytes) =>
      DocumentImportBudget(pages: pages - pageCount, bytes: bytes - sizeBytes);
}
