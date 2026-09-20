enum EvidenceExportKind { singleReading, meterHistory }

enum EvidencePhotoMode {
  withoutPhotos,
  currentPhotos,
  allPhotos;

  String labelFor(EvidenceExportKind kind) => switch (this) {
    withoutPhotos => 'Kompakt ohne Anhänge',
    currentPhotos => 'Mit Fotos und PDFs',
    allPhotos => 'Mit allen Fotos (ältere Version)',
  };

  static EvidencePhotoMode fromStoredName(Object? value) {
    if (value is String) {
      for (final mode in values) {
        if (mode.name == value) return mode;
      }
    }
    return EvidencePhotoMode.allPhotos;
  }
}

class EvidenceExportRecord {
  const EvidenceExportRecord({
    required this.id,
    required this.meterId,
    required this.kind,
    required this.readingIds,
    required this.createdAt,
    required this.fileName,
    required this.filePath,
    required this.pdfSha256,
    required this.manifestSha256,
    this.photoMode = EvidencePhotoMode.allPhotos,
  });

  final String id;
  final String meterId;
  final EvidenceExportKind kind;
  final List<String> readingIds;
  final DateTime createdAt;
  final String fileName;
  final String filePath;
  final String pdfSha256;
  final String manifestSha256;
  final EvidencePhotoMode photoMode;

  String? get partLabel {
    final match = RegExp(r'_Teil_(\d+)_von_(\d+)\.pdf$').firstMatch(fileName);
    return match == null ? null : 'Teil ${match[1]} von ${match[2]}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'meterId': meterId,
    'kind': kind.name,
    'readingIds': readingIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'fileName': fileName,
    'filePath': filePath,
    'pdfSha256': pdfSha256,
    'manifestSha256': manifestSha256,
    'photoMode': photoMode.name,
  };

  factory EvidenceExportRecord.fromJson(Map<String, dynamic> json) {
    return EvidenceExportRecord(
      id: json['id'] as String,
      meterId: json['meterId'] as String,
      kind: EvidenceExportKind.values.byName(json['kind'] as String),
      readingIds: (json['readingIds'] as List).cast<String>(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      pdfSha256: json['pdfSha256'] as String,
      manifestSha256: json['manifestSha256'] as String,
      photoMode: EvidencePhotoMode.fromStoredName(json['photoMode']),
    );
  }
}
