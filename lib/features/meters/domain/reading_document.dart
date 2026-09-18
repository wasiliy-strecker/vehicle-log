enum DocumentSource { imported, scanned }

/// Immutable identity for an original PDF. Replacements receive a new ID.
class ReadingDocument {
  const ReadingDocument({
    required this.id,
    required this.fileName,
    required this.path,
    required this.sha256,
    required this.pageCount,
    required this.sizeBytes,
    required this.source,
    required this.addedAt,
  });

  final String id;
  final String fileName;
  final String path;
  final String sha256;
  final int pageCount;
  final int sizeBytes;
  final DocumentSource source;
  final DateTime addedAt;

  ReadingDocument withPath(String value) => ReadingDocument(
    id: id,
    fileName: fileName,
    path: value,
    sha256: sha256,
    pageCount: pageCount,
    sizeBytes: sizeBytes,
    source: source,
    addedAt: addedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'path': path,
    'sha256': sha256,
    'pageCount': pageCount,
    'sizeBytes': sizeBytes,
    'source': source.name,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  factory ReadingDocument.fromJson(Map<String, dynamic> json) =>
      ReadingDocument(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        path: json['path'] as String,
        sha256: json['sha256'] as String,
        pageCount: json['pageCount'] as int,
        sizeBytes: json['sizeBytes'] as int,
        source: DocumentSource.values.byName(json['source'] as String),
        addedAt: DateTime.parse(json['addedAt'] as String),
      );

  static List<ReadingDocument> listFromJson(Object? json) =>
      (json as List? ?? const [])
          .map(
            (item) => ReadingDocument.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
}

/// EUR input is stored as integer cents, never as a floating point amount.
int? parseCostCents(String text) {
  final value = text.trim().replaceFirst(RegExp(r'\s*€$'), '').trim();
  if (value.isEmpty) return null;
  if (!RegExp(r'^\d+(?:[,.]\d{1,2})?$').hasMatch(value)) {
    throw const FormatException(
      'Bitte einen Euro-Betrag ab 0 mit höchstens zwei Nachkommastellen eingeben.',
    );
  }
  final parts = value.replaceAll(',', '.').split('.');
  final euros = int.tryParse(parts.first);
  if (euros == null || euros > 999999999) {
    throw const FormatException('Der Betrag ist zu groß.');
  }
  return euros * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

String costInput(int? cents) => cents == null
    ? ''
    : '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

String formatCost(int? cents) =>
    cents == null ? 'Keine Kostenangabe' : '${costInput(cents)} €';
