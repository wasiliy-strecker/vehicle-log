import 'meter.dart';
import 'reading_document.dart';
export 'reading_document.dart';
import 'reading_value.dart';

enum CareActivity {
  watering('Wartung'),
  fertilizing('Reparatur'),
  repotting('HU/AU'),
  growth('Kilometerstand'),
  custom('Eigene Aktivität');

  static const presets = [watering, fertilizing, repotting, growth];

  const CareActivity(this.label);
  final String label;
}

class CareActivitySelection {
  const CareActivitySelection(this.activity, this.customActivityLabel);

  factory CareActivitySelection.fromText(String text) {
    final label = text.trim();
    if (label.isEmpty) throw ArgumentError('Bitte eine Aktivität angeben.');
    for (final activity in CareActivity.presets) {
      if (activity.label.toLowerCase() == label.toLowerCase()) {
        return CareActivitySelection(activity, null);
      }
    }
    return CareActivitySelection(CareActivity.custom, label);
  }

  final CareActivity activity;
  final String? customActivityLabel;
  String get label => customActivityLabel ?? activity.label;
}

/// Input is ordered by latest edit first, so the latest spelling wins.
List<String> careActivitySuggestions(Iterable<String> customLabels) {
  final labels = <String, String>{
    for (final activity in CareActivity.presets)
      activity.label.toLowerCase(): activity.label,
  };
  for (final raw in customLabels) {
    final label = raw.trim();
    if (label.isNotEmpty) labels.putIfAbsent(label.toLowerCase(), () => label);
  }
  final custom = labels.values.skip(CareActivity.presets.length).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [...CareActivity.presets.map((activity) => activity.label), ...custom];
}

enum ReadingSource { camera, gallery, manual }

extension ReadingSourceX on ReadingSource {
  String get label => switch (this) {
    ReadingSource.camera => 'Kameraaufnahme',
    ReadingSource.gallery => 'Galerieimport',
    ReadingSource.manual => 'Manuell erfasst',
  };
}

enum LowerReadingReason { meterReplacement, rollover, correction, other }

extension LowerReadingReasonX on LowerReadingReason {
  String get label => switch (this) {
    LowerReadingReason.meterReplacement => 'Neu abgelesen',
    LowerReadingReason.rollover => 'Tachotausch',
    LowerReadingReason.correction => 'Korrektur eines früheren Eintrags',
    LowerReadingReason.other => 'Anderer Grund',
  };
}

class ReadingPhotoVersion {
  const ReadingPhotoVersion({
    required this.id,
    required this.path,
    required this.sha256,
    required this.source,
    required this.addedAt,
    required this.ocrRawText,
    required this.ocrCandidate,
    this.ocrConfidence,
  });

  final String id;
  final String path;
  final String sha256;
  final ReadingSource source;
  final DateTime addedAt;
  final String ocrRawText;
  final String ocrCandidate;
  final double? ocrConfidence;

  ReadingPhotoVersion copyWith({String? path, String? sha256}) =>
      ReadingPhotoVersion(
        id: id,
        path: path ?? this.path,
        sha256: sha256 ?? this.sha256,
        source: source,
        addedAt: addedAt,
        ocrRawText: ocrRawText,
        ocrCandidate: ocrCandidate,
        ocrConfidence: ocrConfidence,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'sha256': sha256,
    'source': source.name,
    'addedAt': addedAt.toUtc().toIso8601String(),
    'ocrRawText': ocrRawText,
    'ocrCandidate': ocrCandidate,
    'ocrConfidence': ocrConfidence,
  };

  factory ReadingPhotoVersion.fromJson(Map<String, dynamic> json) {
    return ReadingPhotoVersion(
      id: json['id'] as String,
      path: json['path'] as String,
      sha256: json['sha256'] as String,
      source: ReadingSource.values.byName(json['source'] as String),
      addedAt: DateTime.parse(json['addedAt'] as String),
      ocrRawText: json['ocrRawText'] as String? ?? '',
      ocrCandidate: json['ocrCandidate'] as String? ?? '',
      ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble(),
    );
  }
}

class MeterReading {
  const MeterReading({
    required this.id,
    required this.meterId,
    required this.meter,
    required this.value,
    required this.capturedAt,
    required this.timezoneOffsetMinutes,
    required this.storedAt,
    required this.updatedAt,
    required this.source,
    required this.photoPath,
    required this.photoSha256,
    required this.ocrRawText,
    required this.ocrCandidate,
    required this.manifestSha256,
    this.ocrConfidence,
    this.photoAddedAt,
    this.photoHistory = const [],
    this.photos,
    this.lowerReadingReason,
    this.note = '',
    this.activity = CareActivity.growth,
    this.customActivityLabel,
    this.hasMeasurement = true,
    this.workshop = '',
    this.costCents,
    this.documents = const [],
    this.documentHistory = const [],
  });

  final String id;
  final String meterId;
  final MeterSnapshot meter;
  final ReadingValue value;
  final DateTime capturedAt;
  final int timezoneOffsetMinutes;
  final DateTime storedAt;
  final DateTime updatedAt;
  final ReadingSource source;
  final String photoPath;
  final String photoSha256;
  final String ocrRawText;
  final String ocrCandidate;
  final double? ocrConfidence;
  final DateTime? photoAddedAt;
  final List<ReadingPhotoVersion> photoHistory;

  /// Null preserves the original single-photo representation and its hash.
  /// An explicit empty list means all current photos were removed.
  final List<ReadingPhotoVersion>? photos;
  final LowerReadingReason? lowerReadingReason;
  final String note;
  final String manifestSha256;
  final CareActivity activity;
  final String? customActivityLabel;
  final bool hasMeasurement;
  final String workshop;
  final int? costCents;
  final List<ReadingDocument> documents;
  final List<ReadingDocument> documentHistory;
  List<ReadingDocument> get allDocuments => [...documentHistory, ...documents];
  bool get hasAttachments => hasPhoto || documents.isNotEmpty;

  String get activityLabel =>
      activity == CareActivity.custom ? customActivityLabel! : activity.label;

  String get measurementText => hasMeasurement
      ? '${value.displayText} ${meter.unit}'
      : 'Ohne Kilometerangabe';

  String get summary =>
      hasMeasurement ? '$activityLabel · $measurementText' : activityLabel;

  bool canCompareGrowthWith(MeterReading other) =>
      hasMeasurement && other.hasMeasurement && meter.unit == other.meter.unit;

  /// An attachment can exist in the record even if its local file is missing.
  bool get hasPhoto => currentPhotos.isNotEmpty;

  bool get wasManuallyCorrected {
    if (!hasPhoto || !hasMeasurement) return false;
    final parsed = ReadingValue.tryParse(ocrCandidate);
    return parsed == null || parsed.compareTo(value) != 0;
  }

  bool get wasFutureAtStorage => capturedAt.isAfter(storedAt);

  DateTime get effectivePhotoAddedAt => photoAddedAt ?? storedAt;

  ReadingPhotoVersion? get _legacyPhoto => source == ReadingSource.manual
      ? null
      : ReadingPhotoVersion(
          id: '${id}_current_photo',
          path: photoPath,
          sha256: photoSha256,
          source: source,
          addedAt: effectivePhotoAddedAt,
          ocrRawText: ocrRawText,
          ocrCandidate: ocrCandidate,
          ocrConfidence: ocrConfidence,
        );

  List<ReadingPhotoVersion> get currentPhotos => photos ?? [?_legacyPhoto];

  ReadingPhotoVersion? get currentPhotoVersion => currentPhotos.firstOrNull;

  List<ReadingPhotoVersion> get allPhotoVersions => [
    ...photoHistory,
    ...currentPhotos,
  ];

  Set<String> get allPhotoPaths => {
    ...allPhotoVersions.map((version) => version.path),
  };

  MeterReading copyWith({
    ReadingValue? value,
    DateTime? capturedAt,
    int? timezoneOffsetMinutes,
    DateTime? updatedAt,
    ReadingSource? source,
    String? photoPath,
    String? photoSha256,
    String? ocrRawText,
    String? ocrCandidate,
    double? ocrConfidence,
    bool clearOcrConfidence = false,
    DateTime? photoAddedAt,
    List<ReadingPhotoVersion>? photoHistory,
    List<ReadingPhotoVersion>? photos,
    LowerReadingReason? lowerReadingReason,
    bool clearLowerReadingReason = false,
    String? note,
    String? manifestSha256,
    CareActivity? activity,
    String? customActivityLabel,
    bool? hasMeasurement,
    String? workshop,
    int? costCents,
    bool clearCost = false,
    List<ReadingDocument>? documents,
    List<ReadingDocument>? documentHistory,
  }) {
    return MeterReading(
      id: id,
      meterId: meterId,
      meter: meter,
      value: value ?? this.value,
      capturedAt: capturedAt ?? this.capturedAt,
      timezoneOffsetMinutes:
          timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
      storedAt: storedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      photoPath: photoPath ?? this.photoPath,
      photoSha256: photoSha256 ?? this.photoSha256,
      ocrRawText: ocrRawText ?? this.ocrRawText,
      ocrCandidate: ocrCandidate ?? this.ocrCandidate,
      ocrConfidence: clearOcrConfidence
          ? null
          : ocrConfidence ?? this.ocrConfidence,
      photoAddedAt: photoAddedAt ?? this.photoAddedAt,
      photoHistory: photoHistory ?? this.photoHistory,
      photos:
          photos ??
          (this.photos == null
              ? null
              : [
                  for (final (index, photo) in this.photos!.indexed)
                    index == 0 && (photoPath != null || photoSha256 != null)
                        ? photo.copyWith(path: photoPath, sha256: photoSha256)
                        : photo,
                ]),
      lowerReadingReason: clearLowerReadingReason
          ? null
          : lowerReadingReason ?? this.lowerReadingReason,
      note: note ?? this.note,
      manifestSha256: manifestSha256 ?? this.manifestSha256,
      activity: activity ?? this.activity,
      customActivityLabel: (activity ?? this.activity) == CareActivity.custom
          ? customActivityLabel ?? this.customActivityLabel
          : null,
      hasMeasurement: hasMeasurement ?? this.hasMeasurement,
      workshop: workshop ?? this.workshop,
      costCents: clearCost ? null : costCents ?? this.costCents,
      documents: documents ?? this.documents,
      documentHistory: documentHistory ?? this.documentHistory,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'meterId': meterId,
    'meter': meter.toJson(),
    'value': value.toJson(),
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
    'storedAt': storedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'source': source.name,
    'photoPath': photoPath,
    'photoSha256': photoSha256,
    'ocrRawText': ocrRawText,
    'ocrCandidate': ocrCandidate,
    'ocrConfidence': ocrConfidence,
    'photoAddedAt': photoAddedAt?.toUtc().toIso8601String(),
    'photoHistory': photoHistory.map((version) => version.toJson()).toList(),
    if (photos != null)
      'photos': photos!.map((photo) => photo.toJson()).toList(),
    'lowerReadingReason': lowerReadingReason?.name,
    'note': note,
    'manifestSha256': manifestSha256,
    'activity': activity.name,
    if (activity == CareActivity.custom)
      'customActivityLabel': customActivityLabel,
    'hasMeasurement': hasMeasurement,
    if (workshop.isNotEmpty) 'workshop': workshop,
    if (costCents != null) 'costCents': costCents,
    if (documents.isNotEmpty)
      'documents': documents.map((d) => d.toJson()).toList(),
    if (documentHistory.isNotEmpty)
      'documentHistory': documentHistory.map((d) => d.toJson()).toList(),
  };

  factory MeterReading.fromJson(Map<String, dynamic> json) {
    final lowerReason = json['lowerReadingReason'] as String?;
    final activity = CareActivity.values.byName(
      json['activity'] as String? ?? 'growth',
    );
    final customLabel = json['customActivityLabel'] as String?;
    if (activity == CareActivity.custom &&
        (customLabel == null || customLabel.trim().isEmpty)) {
      throw const FormatException(
        'Eine eigene Aktivität benötigt eine Bezeichnung.',
      );
    }
    return MeterReading(
      id: json['id'] as String,
      meterId: json['meterId'] as String,
      meter: MeterSnapshot.fromJson(
        Map<String, dynamic>.from(json['meter'] as Map),
      ),
      value: ReadingValue.fromJson(
        Map<String, dynamic>.from(json['value'] as Map),
      ),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      timezoneOffsetMinutes: (json['timezoneOffsetMinutes'] as num).toInt(),
      storedAt: DateTime.parse(json['storedAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      source: ReadingSource.values.byName(json['source'] as String),
      photoPath: json['photoPath'] as String,
      photoSha256: json['photoSha256'] as String,
      ocrRawText: json['ocrRawText'] as String? ?? '',
      ocrCandidate: json['ocrCandidate'] as String? ?? '',
      ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble(),
      photoAddedAt: json['photoAddedAt'] == null
          ? null
          : DateTime.parse(json['photoAddedAt'] as String),
      photoHistory:
          (json['photoHistory'] as List?)
              ?.map(
                (item) => ReadingPhotoVersion.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false) ??
          const [],
      photos: (json['photos'] as List?)
          ?.map(
            (item) => ReadingPhotoVersion.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      lowerReadingReason: lowerReason == null
          ? null
          : LowerReadingReason.values.byName(lowerReason),
      note: json['note'] as String? ?? '',
      manifestSha256: json['manifestSha256'] as String,
      activity: activity,
      customActivityLabel: activity == CareActivity.custom ? customLabel : null,
      hasMeasurement: json['hasMeasurement'] as bool? ?? true,
      workshop: json['workshop'] as String? ?? '',
      costCents: json['costCents'] as int?,
      documents: ReadingDocument.listFromJson(json['documents']),
      documentHistory: ReadingDocument.listFromJson(json['documentHistory']),
    );
  }
}

class ReadingChange {
  const ReadingChange({required this.before, required this.after});

  final String before;
  final String after;

  Map<String, dynamic> toJson() => {'before': before, 'after': after};

  factory ReadingChange.fromJson(Map<String, dynamic> json) => ReadingChange(
    before: json['before'] as String? ?? '',
    after: json['after'] as String? ?? '',
  );
}

class ReadingPhotoChange {
  const ReadingPhotoChange({required this.beforeIds, required this.afterIds});
  final List<String> beforeIds;
  final List<String> afterIds;

  Map<String, dynamic> toJson() => {
    'beforeIds': beforeIds,
    'afterIds': afterIds,
  };
  factory ReadingPhotoChange.fromJson(Map<String, dynamic> json) =>
      ReadingPhotoChange(
        beforeIds: (json['beforeIds'] as List).cast<String>(),
        afterIds: (json['afterIds'] as List).cast<String>(),
      );
}

class ReadingRevision {
  const ReadingRevision({
    required this.id,
    required this.readingId,
    required this.changedAt,
    required this.reason,
    required this.changes,
    this.photoChange,
    this.documentChange,
  });

  final String id;
  final String readingId;
  final DateTime changedAt;
  final String reason;
  final Map<String, ReadingChange> changes;
  final ReadingPhotoChange? photoChange;
  final ReadingPhotoChange? documentChange;

  Map<String, dynamic> toJson() => {
    'id': id,
    'readingId': readingId,
    'changedAt': changedAt.toUtc().toIso8601String(),
    'reason': reason,
    'changes': changes.map((key, value) => MapEntry(key, value.toJson())),
    if (photoChange != null) 'photoChange': photoChange!.toJson(),
    if (documentChange != null) 'documentChange': documentChange!.toJson(),
  };

  factory ReadingRevision.fromJson(Map<String, dynamic> json) {
    final changes = Map<String, dynamic>.from(json['changes'] as Map);
    return ReadingRevision(
      id: json['id'] as String,
      readingId: json['readingId'] as String,
      changedAt: DateTime.parse(json['changedAt'] as String),
      reason: json['reason'] as String,
      documentChange: json['documentChange'] == null
          ? null
          : ReadingPhotoChange.fromJson(
              Map<String, dynamic>.from(json['documentChange'] as Map),
            ),
      photoChange: json['photoChange'] == null
          ? null
          : ReadingPhotoChange.fromJson(
              Map<String, dynamic>.from(json['photoChange'] as Map),
            ),
      changes: changes.map(
        (key, value) => MapEntry(
          key,
          ReadingChange.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
  }
}
