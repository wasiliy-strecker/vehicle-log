import 'package:flutter/foundation.dart';

import '../../../core/files/meter_photo_repository.dart';
import '../../../core/files/document_repository.dart';
import '../../../core/files/photo_draft_store.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/meter_reading.dart';
import '../domain/meter_repositories.dart';

/// Owns only new files. Persisted current and historical photos are never deleted
/// by an abandoned editor. The pending operation survives an Android picker restart.
class ReadingPhotoSession extends ChangeNotifier {
  ReadingPhotoSession({
    required this.route,
    required this.repository,
    required this.store,
    required this.readings,
    this.original,
    this.documentRepository,
  }) : photos = [...?original?.currentPhotos],
       documents = [...?original?.documents];

  final String route;
  final MeterPhotoCaptureRepository repository;
  final PhotoDraftStore store;
  final MeterReadingRepository readings;
  final MeterReading? original;
  final List<ReadingPhotoVersion> photos;
  final DocumentRepository? documentRepository;
  final List<ReadingDocument> documents;
  final Set<String> _ownedDocuments = {};
  bool _pendingDocument = false;
  final Set<String> _owned = {};
  final Map<String, Future<void>> _deletions = {};
  Map<String, dynamic> fields = {};
  String readingId = newLocalId('reading');
  bool busy = false;
  bool _closed = false;
  bool _committed = false;
  Future<void> _pendingWrite = Future.value();
  String progress = '';

  bool get changed =>
      !listEquals(
        documents.map((d) => d.id).toList(),
        (original?.documents ?? []).map((d) => d.id).toList(),
      ) ||
      !listEquals(
        photos.map((p) => p.id).toList(),
        (original?.currentPhotos ?? []).map((p) => p.id).toList(),
      );

  Future<void> _persist({ReadingSource? source, String? replacementId}) {
    if (_closed || _committed) return Future.value();
    final draft = <String, dynamic>{
      'readingId': readingId,
      'originalUpdatedAt': original?.updatedAt.toIso8601String(),
      'photos': photos.map((photo) => photo.toJson()).toList(),
      'ownedPaths': _owned.toList(),
      'documents': documents.map((d) => d.toJson()).toList(),
      'ownedDocuments': _ownedDocuments.toList(),
      'pendingDocument': _pendingDocument,
      'fields': Map<String, dynamic>.of(fields),
      if (source != null) 'pendingSource': source.name,
      'replacementId': ?replacementId,
    };
    final writing = _pendingWrite.then((_) async {
      if (!_closed && !_committed) await store.write(route, draft);
    });
    // Closing must wait for an in-flight write before removing its draft.
    _pendingWrite = writing.then<void>((_) {}, onError: (Object _) {});
    return writing;
  }

  Future<PhotoImportResult> restore() async {
    if (busy || _closed) return const PhotoImportResult();
    busy = true;
    notifyListeners();
    try {
      final draft = await store.read(route);
      if (_closed || draft == null) return const PhotoImportResult();
      readingId = draft['readingId'] as String? ?? readingId;
      _owned.addAll((draft['ownedPaths'] as List).cast<String>());
      _ownedDocuments.addAll(
        (draft['ownedDocuments'] as List? ?? []).cast<String>(),
      );
      final references = (await readings.loadAll())
          .expand(
            (r) => [...r.allPhotoPaths, ...r.allDocuments.map((d) => d.path)],
          )
          .toSet();
      if (_closed) return const PhotoImportResult();
      // A commit may have completed immediately before the process stopped.
      if ((original == null && await readings.findById(readingId) != null) ||
          _owned.any(references.contains) ||
          _ownedDocuments.any(references.contains) ||
          draft['originalUpdatedAt'] != original?.updatedAt.toIso8601String()) {
        await _discard();
        return const PhotoImportResult();
      }
      photos
        ..clear()
        ..addAll(
          (draft['photos'] as List).map(
            (p) => ReadingPhotoVersion.fromJson(
              Map<String, dynamic>.from(p as Map),
            ),
          ),
        );
      documents
        ..clear()
        ..addAll(ReadingDocument.listFromJson(draft['documents']));
      fields = Map<String, dynamic>.from(draft['fields'] as Map);
      if (draft['pendingDocument'] == true) {
        _pendingDocument = false;
        await _persist();
      }
      if (draft['pendingSource'] case final String source) {
        final PhotoImportResult result;
        try {
          result = await repository.recoverPhotos(
            source: ReadingSource.values.byName(source),
            onProgress: _progress,
          );
        } on Object {
          // The picker has returned. Keep the form, but do not retry a consumed
          // recovery operation on every launch.
          await _persist();
          rethrow;
        }
        await _accept(result, replacementId: draft['replacementId'] as String?);
        return result;
      }
      return const PhotoImportResult();
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<PhotoImportResult> capture(
    ReadingSource source, {
    required Map<String, dynamic> formFields,
    String? replacementId,
  }) async {
    if (busy || _closed) return const PhotoImportResult();
    busy = true;
    fields = formFields;
    progress = 'Fotos werden vorbereitet …';
    notifyListeners();
    try {
      await _persist(source: source, replacementId: replacementId);
      if (_closed) return const PhotoImportResult();
      final PhotoImportResult result;
      if (source == ReadingSource.gallery && replacementId == null) {
        result = await repository.pickGalleryPhotos(onProgress: _progress);
      } else {
        final photo = await repository.capture(source);
        result = PhotoImportResult(photos: [?photo]);
      }
      await _accept(result, replacementId: replacementId);
      return result;
    } on Object {
      // A returned picker error is not an outstanding external operation.
      if (!_closed) {
        try {
          await _persist();
        } on Object {
          /* Keep the last durable draft. */
        }
      }
      rethrow;
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  void _progress(int completed, int total) {
    progress = 'Fotos werden vorbereitet: $completed von $total';
    if (!_closed) notifyListeners();
  }

  Future<void> _accept(
    PhotoImportResult result, {
    String? replacementId,
  }) async {
    if (_closed) {
      for (final photo in result.photos) {
        await repository.delete(photo.path);
      }
      return;
    }
    final previous = List<ReadingPhotoVersion>.of(photos);
    for (final picked in result.photos) {
      final photo = ReadingPhotoVersion(
        id: newLocalId('photo_version'),
        path: picked.path,
        sha256: picked.sha256,
        source: picked.source,
        addedAt: picked.capturedAt.toUtc(),
        ocrRawText: '',
        ocrCandidate: '',
      );
      _owned.add(photo.path);
      final index = replacementId == null
          ? -1
          : photos.indexWhere((p) => p.id == replacementId);
      if (index >= 0) {
        photos[index] = photo;
        replacementId = null;
      } else {
        photos.add(photo);
      }
    }
    try {
      await _persist();
    } on Object {
      photos
        ..clear()
        ..addAll(previous);
      // Only newly imported files are owned. Saved originals remain intact.
      await _cleanUnused();
      rethrow;
    }
    await _cleanUnused();
  }

  Future<void> removePhoto(String id, Map<String, dynamic> formFields) async {
    if (busy || _closed) return;
    fields = formFields;
    final index = photos.indexWhere((photo) => photo.id == id);
    if (index < 0) return;
    busy = true;
    progress = 'Foto wird entfernt …';
    final removed = photos.removeAt(index);
    notifyListeners();
    try {
      try {
        await _persist();
      } on Object {
        photos.insert(index, removed);
        rethrow;
      }
      await _cleanUnused();
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> reorderPhotos(
    List<String> orderedIds,
    Map<String, dynamic> formFields,
  ) async {
    if (busy || _closed) return;
    final byId = {for (final photo in photos) photo.id: photo};
    if (orderedIds.length != photos.length ||
        orderedIds.toSet().length != photos.length ||
        !orderedIds.every(byId.containsKey)) {
      throw ArgumentError(
        'Die Fotoreihenfolge muss alle aktuellen Fotos enthalten.',
      );
    }
    if (listEquals(orderedIds, photos.map((photo) => photo.id).toList())) {
      return;
    }
    final previous = List<ReadingPhotoVersion>.of(photos);
    fields = formFields;
    busy = true;
    progress = 'Fotoreihenfolge wird gesichert …';
    photos
      ..clear()
      ..addAll(orderedIds.map((id) => byId[id]!));
    notifyListeners();
    try {
      await _persist();
    } on Object {
      photos
        ..clear()
        ..addAll(previous);
      rethrow;
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _cleanUnused() async {
    if (_closed) return;
    final used = photos.map((p) => p.path).toSet();
    for (final path in _owned.toList()) {
      if (_closed) return;
      if (!used.contains(path)) {
        await _deleteOwned(path);
      }
    }
    await _persist();
  }

  Future<void> _deleteOwned(String path) =>
      _deletions.putIfAbsent(path, () async {
        try {
          await repository.delete(path);
          _owned.remove(path);
        } finally {
          _deletions.remove(path);
        }
      });

  Future<void> rememberFields(Map<String, dynamic> formFields) async {
    if (busy || _closed) return;
    busy = true;
    fields = formFields;
    notifyListeners();
    try {
      await _persist();
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> committed() async {
    _committed = true;
    _owned.clear();
    _ownedDocuments.clear();
    // A stale draft is recognized against saved photo references on recovery.
    try {
      await _pendingWrite;
      await store.remove(route);
    } on Object {
      /* The reading is committed. */
    }
  }

  Future<void> discard() async {
    if (busy || _closed) return;
    busy = true;
    progress = 'Ungespeicherte Anhänge werden entfernt …';
    notifyListeners();
    try {
      await _discard();
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _discard() async {
    final references = (await readings.loadAll())
        .expand(
          (r) => [...r.allPhotoPaths, ...r.allDocuments.map((d) => d.path)],
        )
        .toSet();
    for (final path in _owned.toList()) {
      if (references.contains(path)) {
        _owned.remove(path);
      } else {
        await _deleteOwned(path);
      }
    }
    for (final path in _ownedDocuments.toList()) {
      if (references.contains(path)) {
        _ownedDocuments.remove(path);
      } else {
        await _deleteOwnedDocument(path);
      }
    }
    await store.remove(route);
    documents
      ..clear()
      ..addAll(original?.documents ?? []);
    photos
      ..clear()
      ..addAll(original?.currentPhotos ?? []);
    fields = {};
    readingId = newLocalId('reading');
  }

  Future<DocumentImportResult> captureDocuments({
    required bool scan,
    required Map<String, dynamic> formFields,
    String? replacementId,
  }) async {
    if (busy || _closed) return const DocumentImportResult();
    busy = true;
    fields = formFields;
    _pendingDocument = true;
    progress = scan ? 'Dokument wird gescannt …' : 'PDFs werden vorbereitet …';
    notifyListeners();
    try {
      await _persist();
      if (_closed) return const DocumentImportResult();
      final result = scan
          ? await documentRepository!.scan()
          : await documentRepository!.pick(multiple: replacementId == null);
      if (_closed) {
        for (final doc in result.documents) {
          await documentRepository!.delete(doc.path);
        }
        return const DocumentImportResult();
      }
      final previous = List<ReadingDocument>.of(documents);
      for (final doc in result.documents) {
        _ownedDocuments.add(doc.path);
        final index = replacementId == null
            ? -1
            : documents.indexWhere((d) => d.id == replacementId);
        if (index < 0) {
          documents.add(doc);
        } else {
          documents[index] = doc;
          replacementId = null;
        }
      }
      _pendingDocument = false;
      try {
        await _persist();
      } catch (_) {
        documents
          ..clear()
          ..addAll(previous);
        await _cleanUnusedDocuments();
        rethrow;
      }
      await _cleanUnusedDocuments();
      return result;
    } finally {
      _pendingDocument = false;
      if (!_closed) {
        try {
          await _persist();
        } catch (_) {}
      }
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> changeDocuments(
    List<ReadingDocument> next,
    Map<String, dynamic> formFields,
  ) async {
    if (busy || _closed) return;
    final currentIds = documents.map((d) => d.id).toSet();
    if (next.map((d) => d.id).toSet().length != next.length ||
        next.any((d) => !currentIds.contains(d.id))) {
      throw ArgumentError('Ungültige Dokumentreihenfolge.');
    }
    final previous = List<ReadingDocument>.of(documents);
    busy = true;
    fields = formFields;
    documents
      ..clear()
      ..addAll(next);
    notifyListeners();
    try {
      try {
        await _persist();
      } catch (_) {
        documents
          ..clear()
          ..addAll(previous);
        rethrow;
      }
      await _cleanUnusedDocuments();
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _cleanUnusedDocuments() async {
    if (_closed) return;
    for (final path in _ownedDocuments.toList()) {
      if (_closed) return;
      if (!documents.any((d) => d.path == path)) {
        await _deleteOwnedDocument(path);
      }
    }
    await _persist();
  }

  Future<void> _deleteOwnedDocument(String path) =>
      _deletions.putIfAbsent('document:$path', () async {
        try {
          await documentRepository!.delete(path);
          _ownedDocuments.remove(path);
        } finally {
          _deletions.remove('document:$path');
        }
      });

  Future<void> close() async {
    _closed = true;
    await _pendingWrite;
    if (!_committed) await _discard();
  }
}
