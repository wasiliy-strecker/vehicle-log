import '../../../core/files/pdf_limits.dart';
import 'dart:async';

import 'package:universal_io/io.dart';

import '../../../core/files/evidence_photo_asset_repository.dart';
import '../../../core/files/meter_photo_repository.dart';
import '../../../core/integrity/integrity_service.dart';
import '../../../core/persistence/repository_transaction.dart';
import '../../../core/reminders/local_notification_reminder_repository.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/reading_time.dart';
import '../../evidence/domain/evidence_export.dart';
import '../domain/meter.dart';
import '../domain/meter_reading.dart';
import '../domain/meter_repositories.dart';
import '../domain/reading_value.dart';

class MeterService {
  const MeterService({
    required this.meters,
    required this.readings,
    required this.exports,
    required this.photos,
    required this.reminders,
    this.evidencePhotos = const NoopEvidencePhotoAssetRepository(),
    this.transaction = runWithoutTransaction,
  });

  final MeterRepository meters;
  final MeterReadingRepository readings;
  final EvidenceExportRepository exports;
  final MeterPhotoCaptureRepository photos;
  final MeterReminderRepository reminders;
  final EvidencePhotoAssetRepository evidencePhotos;
  final RepositoryTransaction transaction;

  Future<Meter> create({
    required String label,
    required MeterType type,
    required String unit,
    required String meterNumber,
    required String location,
    String vin = '',
    String firstRegistration = '',
    ReadingReminderSchedule? reminder,
  }) async {
    final now = DateTime.now().toUtc();
    final meter = Meter(
      id: newLocalId('meter'),
      label: label.trim(),
      type: type,
      unit: unit.trim(),
      meterNumber: meterNumber.trim(),
      location: location.trim(),
      vin: vin.trim(),
      firstRegistration: firstRegistration.trim(),
      createdAt: now,
      updatedAt: now,
      reminder: reminder,
    );
    await meters.save(meter);
    await reminders.schedule(meter);
    return meter;
  }

  Future<void> update(Meter meter) async {
    final updated = meter.copyWith(updatedAt: DateTime.now().toUtc());
    await meters.save(updated);
    await reminders.schedule(
      updated,
      latestReading: _latestReading(await readings.loadForMeter(updated.id)),
    );
  }

  Future<void> delete(String meterId) async {
    if (await reminders.cancel(meterId) == ReminderOperationResult.failed) {
      throw StateError(
        'Die Erinnerung konnte nicht ausgeschaltet werden. Bitte erneut versuchen.',
      );
    }
    final meterReadings = await readings.loadForMeter(meterId);
    final evidenceExports = await exports.loadForMeter(meterId);
    await transaction(() async {
      for (final reading in meterReadings) {
        await readings.delete(reading.id);
      }
      for (final export in evidenceExports) {
        await exports.delete(export.id);
      }
      await meters.delete(meterId);
    });
    await _cleanDeletedFiles(
      deletedReadings: meterReadings,
      deletedExports: evidenceExports,
      readings: readings,
      exports: exports,
      photos: photos,
      evidencePhotos: evidencePhotos,
    );
  }
}

class MeterReadingService {
  const MeterReadingService({
    required this.meters,
    required this.readings,
    required this.exports,
    required this.photos,
    required this.reminders,
    this.integrity = const IntegrityService(),
    this.evidencePhotos = const NoopEvidencePhotoAssetRepository(),
    this.transaction = runWithoutTransaction,
  });

  final MeterRepository meters;
  final MeterReadingRepository readings;
  final EvidenceExportRepository exports;
  final MeterPhotoCaptureRepository photos;
  final MeterReminderRepository reminders;
  final IntegrityService integrity;
  final EvidencePhotoAssetRepository evidencePhotos;
  final RepositoryTransaction transaction;

  Future<MeterReading> create({
    required Meter meter,
    required StoredMeterPhoto photo,
    required ReadingValue value,
    required DateTime capturedAt,
    required String note,
    CareActivity activity = CareActivity.growth,
    String? customActivityLabel,
    bool hasMeasurement = true,
    String workshop = '',
    int? costCents,
    List<ReadingDocument> documents = const [],
  }) {
    if (photo.source == ReadingSource.manual) {
      throw ArgumentError('Ein Foto benötigt eine Kamera- oder Galeriequelle.');
    }
    return _create(
      meter: meter,
      photo: photo,
      value: value,
      capturedAt: capturedAt,
      note: note,
      activity: activity,
      customActivityLabel: customActivityLabel,
      hasMeasurement: hasMeasurement,
      workshop: workshop.trim(),
      costCents: costCents,
      documents: List.unmodifiable(documents),
    );
  }

  Future<MeterReading> createWithPhotos({
    required Meter meter,
    String? readingId,
    required List<ReadingPhotoVersion> photos,
    required ReadingValue value,
    required DateTime capturedAt,
    required String note,
    CareActivity activity = CareActivity.growth,
    String? customActivityLabel,
    bool hasMeasurement = true,
    String workshop = '',
    int? costCents,
    List<ReadingDocument> documents = const [],
  }) => _create(
    meter: meter,
    readingId: readingId,
    value: value,
    capturedAt: capturedAt,
    note: note,
    photoList: photos,
    activity: activity,
    customActivityLabel: customActivityLabel,
    hasMeasurement: hasMeasurement,
    workshop: workshop.trim(),
    costCents: costCents,
    documents: List.unmodifiable(documents),
  );

  Future<MeterReading> createManual({
    required Meter meter,
    required ReadingValue value,
    required DateTime capturedAt,
    required String note,
    CareActivity activity = CareActivity.growth,
    String? customActivityLabel,
    bool hasMeasurement = true,
    String workshop = '',
    int? costCents,
    List<ReadingDocument> documents = const [],
  }) => _create(
    meter: meter,
    value: value,
    capturedAt: capturedAt,
    note: note,
    activity: activity,
    customActivityLabel: customActivityLabel,
    hasMeasurement: hasMeasurement,
    workshop: workshop.trim(),
    costCents: costCents,
    documents: List.unmodifiable(documents),
  );

  Future<MeterReading> _create({
    required Meter meter,
    required ReadingValue value,
    required DateTime capturedAt,
    required String note,
    CareActivity activity = CareActivity.growth,
    String? customActivityLabel,
    bool hasMeasurement = true,
    String workshop = '',
    int? costCents,
    List<ReadingDocument> documents = const [],
    StoredMeterPhoto? photo,
    List<ReadingPhotoVersion>? photoList,
    String? readingId,
  }) async {
    final selection = CareActivitySelection.fromText(
      activity == CareActivity.custom
          ? customActivityLabel ?? ''
          : activity.label,
    );
    activity = selection.activity;
    customActivityLabel = selection.customActivityLabel;
    final currentPhotos =
        photoList ?? [if (photo != null) _photoVersion(photo)];
    _validatePhotos(currentPhotos);
    _validateDocuments(documents);
    _validateDocumentBudget(const [], documents);
    _validateCost(costCents);
    final first = currentPhotos.firstOrNull;
    value = hasMeasurement
        ? _validateValue(value)
        : ReadingValue.tryParseWhole('0')!;
    final now = storageTimestamp(DateTime.now());
    var reading = MeterReading(
      id: readingId ?? newLocalId('reading'),
      meterId: meter.id,
      meter: MeterSnapshot.fromMeter(meter),
      value: value,
      capturedAt: storageTimestamp(capturedAt),
      timezoneOffsetMinutes: capturedAt.timeZoneOffset.inMinutes,
      storedAt: now,
      updatedAt: now,
      source: first?.source ?? ReadingSource.manual,
      photoPath: first?.path ?? '',
      photoSha256: first?.sha256 ?? '',
      ocrRawText: '',
      ocrCandidate: '',
      ocrConfidence: null,
      photoAddedAt: first?.addedAt,
      photos: List.unmodifiable(currentPhotos),
      note: note.trim(),
      manifestSha256: '',
      activity: activity,
      customActivityLabel: customActivityLabel,
      hasMeasurement: hasMeasurement,
      workshop: workshop.trim(),
      costCents: costCents,
      documents: List.unmodifiable(documents),
    );
    reading = reading.copyWith(
      manifestSha256: await integrity.readingManifestHash(reading),
    );
    await readings.save(reading);
    for (final photo in reading.currentPhotos) {
      _prewarmEvidencePhoto(photo);
    }
    await reminders.acknowledge(meter.id);
    await _refreshReminderSummary(meter.id);
    return reading;
  }

  Future<MeterReading> update({
    required MeterReading existing,
    required ReadingValue value,
    required DateTime capturedAt,
    required String note,
    CareActivity? activity,
    String? customActivityLabel,
    bool? hasMeasurement,
    String? workshop,
    int? costCents,
    bool clearCost = false,
    List<ReadingDocument>? documents,
    StoredMeterPhoto? replacementPhoto,
    List<ReadingPhotoVersion>? photos,
  }) async {
    workshop = (workshop ?? existing.workshop).trim();
    costCents = clearCost ? null : costCents ?? existing.costCents;
    documents ??= existing.documents;
    _validateCost(costCents);
    _validateDocuments(documents);
    _validateDocumentBudget(existing.documents, documents);
    final currentDocuments = {for (final d in existing.documents) d.id: d};
    final historicIds = existing.documentHistory.map((d) => d.id).toSet();
    for (final doc in documents) {
      final previous = currentDocuments[doc.id];
      if (historicIds.contains(doc.id) ||
          (previous != null &&
              integrity.canonicalJson(previous.toJson()) !=
                  integrity.canonicalJson(doc.toJson()))) {
        throw ArgumentError('Ein geändertes Dokument benötigt eine neue ID.');
      }
    }
    final beforeDocumentIds = existing.documents.map((d) => d.id).toList();
    final afterDocumentIds = documents.map((d) => d.id).toList();
    final documentsChanged =
        integrity.canonicalJson(beforeDocumentIds) !=
        integrity.canonicalJson(afterDocumentIds);
    activity ??= existing.activity;
    final selection = CareActivitySelection.fromText(
      activity == CareActivity.custom
          ? customActivityLabel ?? existing.customActivityLabel ?? ''
          : activity.label,
    );
    activity = selection.activity;
    customActivityLabel = selection.customActivityLabel;
    hasMeasurement ??= existing.hasMeasurement;
    if (replacementPhoto?.source == ReadingSource.manual) {
      throw ArgumentError('Ein Foto benötigt eine Kamera- oder Galeriequelle.');
    }
    if (photos != null && replacementPhoto != null) {
      throw ArgumentError(
        'Fotos und Einzelfoto-Ersatz nicht gleichzeitig übergeben.',
      );
    }
    final nextPhotos =
        photos ??
        (replacementPhoto == null
            ? existing.currentPhotos
            : [
                _photoVersion(replacementPhoto),
                ...existing.currentPhotos.skip(1),
              ]);
    _validatePhotos(nextPhotos);
    final currentById = {
      for (final photo in existing.currentPhotos) photo.id: photo,
    };
    final archivedIds = existing.photoHistory.map((photo) => photo.id).toSet();
    for (final photo in nextPhotos) {
      final previous = currentById[photo.id];
      if (archivedIds.contains(photo.id) ||
          (previous != null &&
              integrity.canonicalJson(previous.toJson()) !=
                  integrity.canonicalJson(photo.toJson()))) {
        throw ArgumentError('Ein geändertes Foto benötigt eine neue Foto-ID.');
      }
    }
    final beforeIds = existing.currentPhotos.map((photo) => photo.id).toList();
    final afterIds = nextPhotos.map((photo) => photo.id).toList();
    final photosChanged =
        beforeIds.length != afterIds.length ||
        beforeIds.indexed.any((entry) => entry.$2 != afterIds[entry.$1]);
    value = hasMeasurement
        ? _validateValue(value, existing: existing.value)
        : ReadingValue.tryParseWhole('0')!;
    final changedAt = storageTimestamp(DateTime.now());
    final readingTime = storageTimestamp(capturedAt);
    final timeChanged = !readingTime.isAtSameMomentAs(existing.capturedAt);
    final changed =
        existing.value.displayText != value.displayText ||
        existing.value.compareTo(value) != 0 ||
        timeChanged ||
        existing.note != note.trim() ||
        photosChanged ||
        existing.activity != activity ||
        existing.customActivityLabel != customActivityLabel ||
        existing.hasMeasurement != hasMeasurement ||
        existing.workshop != workshop ||
        existing.costCents != costCents ||
        documentsChanged;
    if (!changed) return existing;

    // Preserve only references belonging to revisions that already exist.
    // Edits themselves no longer produce revision records or archived versions.
    final legacyRevisions = await readings.loadRevisions(existing.id);
    final legacyPhotoIds = <String>{
      for (final revision in legacyRevisions) ...[
        ...?revision.photoChange?.beforeIds,
        ...?revision.photoChange?.afterIds,
      ],
    };
    final legacyPhotoHashes = <String>{
      for (final revision in legacyRevisions)
        if (revision.changes['Prüfwert des Fotos (SHA-256)']
            case final change?) ...[
          change.before,
          change.after,
        ],
    };
    final legacyDocumentIds = <String>{
      for (final revision in legacyRevisions) ...[
        ...?revision.documentChange?.beforeIds,
        ...?revision.documentChange?.afterIds,
      ],
    };
    final archivedPhotos = [
      ...existing.photoHistory,
      for (final photo in existing.currentPhotos)
        if (!afterIds.contains(photo.id) &&
            (legacyPhotoIds.contains(photo.id) ||
                legacyPhotoHashes.contains(photo.sha256)))
          photo,
    ];
    final first = nextPhotos.firstOrNull;
    var updated = existing.copyWith(
      value: value,
      capturedAt: readingTime,
      timezoneOffsetMinutes: timeChanged
          ? capturedAt.timeZoneOffset.inMinutes
          : existing.timezoneOffsetMinutes,
      updatedAt: changedAt,
      source: first?.source ?? ReadingSource.manual,
      photoPath: first?.path ?? '',
      photoSha256: first?.sha256 ?? '',
      ocrRawText: photosChanged ? '' : null,
      ocrCandidate: photosChanged ? '' : null,
      clearOcrConfidence: photosChanged,
      photoAddedAt: first?.addedAt,
      photos: photosChanged ? List.unmodifiable(nextPhotos) : null,
      photoHistory: archivedPhotos,
      documentHistory: [
        ...existing.documentHistory,
        ...existing.documents.where(
          (d) =>
              !afterDocumentIds.contains(d.id) &&
              legacyDocumentIds.contains(d.id),
        ),
      ],
      clearCost: clearCost,
      note: note.trim(),
      manifestSha256: '',
      activity: activity,
      customActivityLabel: customActivityLabel,
      hasMeasurement: hasMeasurement,
      workshop: workshop.trim(),
      costCents: costCents,
      documents: List.unmodifiable(documents),
    );
    updated = updated.copyWith(
      manifestSha256: await integrity.readingManifestHash(updated),
    );
    await readings.save(updated);
    await _cleanRemovedAttachments(existing, updated);
    for (final photo in updated.currentPhotos) {
      if (!beforeIds.contains(photo.id)) _prewarmEvidencePhoto(photo);
    }
    await _refreshReminderSummary(existing.meterId);
    return updated;
  }

  Future<void> _cleanRemovedAttachments(
    MeterReading previous,
    MeterReading updated,
  ) async {
    // Saving is already committed. A failed reference check or file deletion
    // must never be reported as a failed edit or discard the new attachments.
    try {
      final allReadings = await readings.loadAll();
      final referencedPaths = <String>{
        ...updated.allPhotoPaths,
        for (final reading in allReadings) ...reading.allPhotoPaths,
        for (final document in updated.allDocuments) document.path,
        for (final reading in allReadings)
          for (final document in reading.allDocuments) document.path,
      };
      final referencedHashes = <String>{
        for (final photo in updated.allPhotoVersions) photo.sha256,
        for (final reading in allReadings)
          for (final photo in reading.allPhotoVersions) photo.sha256,
      };
      for (final photo in previous.currentPhotos) {
        if (referencedPaths.contains(photo.path)) continue;
        try {
          await photos.delete(photo.path);
          if (!referencedHashes.contains(photo.sha256)) {
            await evidencePhotos.delete(photo.sha256);
          }
        } on Object {
          // Leave an unreferenced file for a later cleanup if storage is busy.
        }
      }
      for (final document in previous.documents) {
        if (referencedPaths.contains(document.path)) continue;
        try {
          final file = File(document.path);
          if (await file.exists()) await file.delete();
        } on Object {
          // The saved entry remains valid even if cleanup needs to be retried.
        }
      }
    } on Object {
      // Keep files when their remaining references cannot be verified.
    }
  }

  Future<void> delete(MeterReading reading) async {
    final singleExports = (await exports.loadForMeter(reading.meterId))
        .where(
          (record) =>
              record.kind == EvidenceExportKind.singleReading &&
              record.readingIds.contains(reading.id),
        )
        .toList();
    await transaction(() async {
      for (final record in singleExports) {
        await exports.delete(record.id);
      }
      await readings.delete(reading.id);
    });
    await _cleanDeletedFiles(
      deletedReadings: [reading],
      deletedExports: singleExports,
      readings: readings,
      exports: exports,
      photos: photos,
      evidencePhotos: evidencePhotos,
    );
    await _refreshReminderSummary(reading.meterId);
  }

  ReadingPhotoVersion _photoVersion(StoredMeterPhoto photo) =>
      ReadingPhotoVersion(
        id: newLocalId('photo_version'),
        path: photo.path,
        sha256: photo.sha256,
        source: photo.source,
        addedAt: storageTimestamp(photo.capturedAt),
        ocrRawText: '',
        ocrCandidate: '',
      );

  void _validateCost(int? cost) {
    if (cost != null && (cost < 0 || cost > 99999999999)) {
      throw const FormatException('Bitte einen gültigen Euro-Betrag angeben.');
    }
  }

  void _validateDocumentBudget(
    List<ReadingDocument> previous,
    List<ReadingDocument> next,
  ) {
    final oldIds = previous.map((d) => d.id).toSet();
    final added = next.where((d) => !oldIds.contains(d.id));
    if (added.isEmpty) return;
    final retained = next.where((d) => oldIds.contains(d.id));
    final oldPages = previous.fold(0, (sum, d) => sum + d.pageCount);
    final oldBytes = previous.fold(0, (sum, d) => sum + d.sizeBytes);
    var budget = DocumentImportBudget(
      pages:
          (oldPages > PdfLimits.entryPages ? oldPages : PdfLimits.entryPages) -
          retained.fold(0, (sum, d) => sum + d.pageCount),
      bytes:
          (oldBytes > PdfLimits.entryBytes ? oldBytes : PdfLimits.entryBytes) -
          retained.fold(0, (sum, d) => sum + d.sizeBytes),
    );
    for (final doc in added) {
      budget.validate(doc.pageCount, doc.sizeBytes);
      budget = budget.consume(doc.pageCount, doc.sizeBytes);
    }
  }

  void _validateDocuments(List<ReadingDocument> documents) {
    if (documents.map((d) => d.id).toSet().length != documents.length ||
        documents.any(
          (d) =>
              d.id.isEmpty ||
              d.path.isEmpty ||
              d.fileName.isEmpty ||
              d.pageCount < 1 ||
              d.sizeBytes < 1 ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(d.sha256),
        )) {
      throw ArgumentError(
        'Dokumente benötigen eindeutige IDs und gültige PDF-Dateien.',
      );
    }
  }

  void _validatePhotos(List<ReadingPhotoVersion> photos) {
    if (photos.map((photo) => photo.id).toSet().length != photos.length ||
        photos.any(
          (photo) =>
              photo.id.isEmpty ||
              photo.path.isEmpty ||
              photo.sha256.isEmpty ||
              photo.source == ReadingSource.manual,
        )) {
      throw ArgumentError(
        'Fotos benötigen eindeutige IDs, Dateien und eine Fotoquelle.',
      );
    }
  }

  ReadingValue _validateValue(ReadingValue value, {ReadingValue? existing}) {
    if (existing != null &&
        value.displayText == existing.displayText &&
        value.digits == existing.digits &&
        value.scale == existing.scale) {
      return existing;
    }
    final parsed = ReadingValue.tryParseWhole(value.displayText);
    if (parsed == null || value.scale != 0 || parsed.digits != value.digits) {
      throw const FormatException('Bitte eine ganze Zahl ab 0 eingeben.');
    }
    return parsed;
  }

  void _prewarmEvidencePhoto(ReadingPhotoVersion photo) {
    unawaited(
      evidencePhotos
          .prepare(path: photo.path, sha256: photo.sha256)
          .then<void>((_) {}, onError: (_) {}),
    );
  }

  Future<void> _refreshReminderSummary(String meterId) async {
    try {
      final meter = await meters.findById(meterId);
      if (meter == null || meter.reminder == null) return;
      await reminders.schedule(
        meter,
        latestReading: _latestReading(await readings.loadForMeter(meterId)),
      );
    } on Object {
      // The entry is already committed. A notification refresh must not make
      // its editor discard newly saved attachments or retry the same creation.
    }
  }

  Future<MeterReading?> previousReading({
    required String meterId,
    required DateTime capturedAt,
    String? excludingId,
  }) async {
    final items = await readings.loadForMeter(meterId);
    final earlier =
        items
            .where(
              (item) =>
                  item.id != excludingId &&
                  item.capturedAt.isBefore(capturedAt),
            )
            .toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return earlier.firstOrNull;
  }
}

Future<void> _cleanDeletedFiles({
  required List<MeterReading> deletedReadings,
  required List<EvidenceExportRecord> deletedExports,
  required MeterReadingRepository readings,
  required EvidenceExportRepository exports,
  required MeterPhotoCaptureRepository photos,
  required EvidencePhotoAssetRepository evidencePhotos,
}) async {
  // Database deletion has committed. Keep files if references cannot be
  // checked, and never turn a cleanup failure into an unsuccessful deletion.
  try {
    final remaining = await readings.loadAll();
    final remainingExports = await exports.loadAll();
    final usedPaths = <String>{
      for (final reading in remaining) ...reading.allPhotoPaths,
      for (final reading in remaining)
        for (final document in reading.allDocuments) document.path,
      for (final record in remainingExports) record.filePath,
    };
    final usedHashes = {
      for (final reading in remaining)
        for (final photo in reading.allPhotoVersions) photo.sha256,
    };
    for (final path in {
      for (final reading in deletedReadings) ...reading.allPhotoPaths,
    }.difference(usedPaths)) {
      try {
        await photos.delete(path);
      } on Object {
        // Leave an unreferenced file if storage cleanup fails.
      }
    }
    for (final hash in {
      for (final reading in deletedReadings)
        for (final photo in reading.allPhotoVersions) photo.sha256,
    }.difference(usedHashes)) {
      try {
        await evidencePhotos.delete(hash);
      } on Object {
        // Cached photos are expendable, but remaining entries still own theirs.
      }
    }
    for (final path in {
      for (final reading in deletedReadings)
        for (final document in reading.allDocuments) document.path,
      for (final record in deletedExports) record.filePath,
    }.difference(usedPaths)) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on Object {
        // The records are gone. Keep an orphan instead of reporting failure.
      }
    }
  } on Object {
    // Never delete files when the remaining references are unknown.
  }
}

MeterReading? _latestReading(List<MeterReading> readings) {
  if (readings.isEmpty) return null;
  return readings.reduce(
    (left, right) => left.capturedAt.isAfter(right.capturedAt) ? left : right,
  );
}
