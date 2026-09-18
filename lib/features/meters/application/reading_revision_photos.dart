import '../domain/meter_reading.dart';

const photoRevisionChangeKeys = {
  'Prüfwert des Fotos (SHA-256)',
  'Fotoquelle',
  'OCR-Kandidat',
};

class ReadingRevisionPhotos {
  const ReadingRevisionPhotos({
    required this.before,
    required this.after,
    this.beforePhotos,
    this.afterPhotos,
  });
  final List<ReadingPhotoVersion>? beforePhotos;
  final List<ReadingPhotoVersion>? afterPhotos;
  List<ReadingPhotoVersion> get beforeList => beforePhotos ?? [?before];
  List<ReadingPhotoVersion> get afterList => afterPhotos ?? [?after];

  final ReadingPhotoVersion? before;
  final ReadingPhotoVersion? after;
}

bool revisionChangesPhoto(ReadingRevision revision) =>
    revision.photoChange != null ||
    revision.changes.keys.any(photoRevisionChangeKeys.contains);

Iterable<MapEntry<String, ReadingChange>> visibleRevisionChanges(
  ReadingRevision revision,
) => revision.changes.entries.where(
  (entry) => !photoRevisionChangeKeys.contains(entry.key),
);

ReadingRevisionPhotos? photosForRevision({
  required MeterReading reading,
  required ReadingRevision revision,
}) {
  if (!revisionChangesPhoto(revision)) return null;

  if (revision.photoChange case final change?) {
    final versions = {
      for (final photo in reading.allPhotoVersions) photo.id: photo,
    };
    final before = [
      for (final id in change.beforeIds)
        if (versions[id] != null) versions[id]!,
    ];
    final after = [
      for (final id in change.afterIds)
        if (versions[id] != null) versions[id]!,
    ];
    return ReadingRevisionPhotos(
      before: before.firstOrNull,
      after: after.firstOrNull,
      beforePhotos: before,
      afterPhotos: after,
    );
  }
  final hashChange = revision.changes['Prüfwert des Fotos (SHA-256)'];
  if (hashChange == null) {
    return const ReadingRevisionPhotos(before: null, after: null);
  }

  final versions = reading.allPhotoVersions;
  return ReadingRevisionPhotos(
    before: _photoBefore(
      versions,
      hash: hashChange.before,
      changedAt: revision.changedAt,
    ),
    after: _photoAfter(
      versions,
      hash: hashChange.after,
      changedAt: revision.changedAt,
    ),
  );
}

ReadingPhotoVersion? _photoBefore(
  List<ReadingPhotoVersion> versions, {
  required String hash,
  required DateTime changedAt,
}) {
  final candidates =
      versions
          .where(
            (version) =>
                version.sha256 == hash && version.addedAt.isBefore(changedAt),
          )
          .toList()
        ..sort((left, right) => right.addedAt.compareTo(left.addedAt));
  if (candidates.isNotEmpty) return candidates.first;
  return _closestPhoto(versions, hash: hash, changedAt: changedAt);
}

ReadingPhotoVersion? _photoAfter(
  List<ReadingPhotoVersion> versions, {
  required String hash,
  required DateTime changedAt,
}) {
  for (final version in versions) {
    if (version.sha256 == hash && version.addedAt.isAtSameMomentAs(changedAt)) {
      return version;
    }
  }
  return _closestPhoto(versions, hash: hash, changedAt: changedAt);
}

ReadingPhotoVersion? _closestPhoto(
  List<ReadingPhotoVersion> versions, {
  required String hash,
  required DateTime changedAt,
}) {
  final candidates = versions
      .where((version) => version.sha256 == hash)
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((left, right) {
    final leftDistance = left.addedAt.difference(changedAt).abs();
    final rightDistance = right.addedAt.difference(changedAt).abs();
    return leftDistance.compareTo(rightDistance);
  });
  return candidates.first;
}
