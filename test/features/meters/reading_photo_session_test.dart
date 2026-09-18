import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/files/photo_draft_store.dart';
import 'package:fahrzeugakte/features/meters/application/reading_photo_session.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';
import 'multiple_photos_test.dart' show testPhoto;

void main() {
  test(
    'closing during file cleanup deletes each owned photo only once',
    () async {
      final repo = _Photos();
      final store = MemoryPhotoDraftStore();
      final session = ReadingPhotoSession(
        route: '/new',
        repository: repo,
        store: store,
        readings: MemoryReadingRepository(),
      );
      await session.capture(ReadingSource.gallery, formFields: {});
      final pending = repo.pendingDelete = Completer<void>();
      final removing = session.removePhoto(session.photos.first.id, {});
      await Future<void>.delayed(Duration.zero);
      expect(repo.deleted, ['/gallery1.jpg']);
      final closing = session.close();
      await Future<void>.delayed(Duration.zero);
      expect(repo.deleted, ['/gallery1.jpg']);
      pending.complete();
      await Future.wait([removing, closing]);
      expect(repo.deleted, ['/gallery1.jpg', '/gallery2.jpg']);
      expect(await store.read('/new'), null);
    },
  );

  for (final source in [ReadingSource.camera, ReadingSource.gallery]) {
    test(
      'cancelled $source replacement preserves saved photos and fields',
      () async {
        final repo = _Photos()..pending = Future.value(null);
        final store = MemoryPhotoDraftStore();
        final original = sampleReading();
        final session = ReadingPhotoSession(
          route: '/edit',
          repository: repo,
          store: store,
          readings: MemoryReadingRepository(),
          original: original,
        );
        final result = await session.capture(
          source,
          formFields: {'value': '34', 'note': 'Nicht verlieren'},
          replacementId: original.currentPhotos.single.id,
        );
        expect(result.photos, isEmpty);
        expect(session.changed, false);
        expect(
          session.photos.single.toJson(),
          original.currentPhotos.single.toJson(),
        );
        expect(session.fields, {'value': '34', 'note': 'Nicht verlieren'});
        expect(await store.pendingRoute(), null);
        expect(repo.deleted, isEmpty);
      },
    );
  }

  test(
    'empty and partially failed gallery selections keep valid photos in order',
    () async {
      final repo = _Photos()..batch = const PhotoImportResult();
      final session = ReadingPhotoSession(
        route: '/new',
        repository: repo,
        store: MemoryPhotoDraftStore(),
        readings: MemoryReadingRepository(),
      );
      await session.capture(ReadingSource.gallery, formFields: {});
      expect(session.photos, isEmpty);
      repo.batch = PhotoImportResult(
        photos: [_photo('good', ReadingSource.gallery)],
        failures: ['broken.jpg'],
      );
      final result = await session.capture(
        ReadingSource.gallery,
        formFields: {},
      );
      expect(result.failures, ['broken.jpg']);
      expect(session.photos.map((p) => p.path), ['/good.jpg']);
      repo.batch = const PhotoImportResult(failures: ['broken.jpg']);
      await session.capture(ReadingSource.gallery, formFields: {});
      expect(session.photos.map((p) => p.path), ['/good.jpg']);
      await session.close();
      expect(repo.deleted, ['/good.jpg']);
    },
  );

  test('failed removal restores the photo at its original position', () async {
    final repo = _Photos();
    final session = ReadingPhotoSession(
      route: '/edit',
      repository: repo,
      store: _FailingStore(),
      readings: MemoryReadingRepository(),
      original: sampleReading().copyWith(
        photos: [testPhoto('a'), testPhoto('b'), testPhoto('c')],
      ),
    );
    await expectLater(session.removePhoto('b', {}), throwsStateError);
    expect(session.photos.map((p) => p.id), ['a', 'b', 'c']);
    expect(session.changed, false);
    expect(session.busy, false);
    expect(repo.deleted, isEmpty);
  });

  test(
    'removal blocks overlapping photo actions until storage finishes',
    () async {
      final store = _ControlledStore();
      final repo = _Photos();
      final original = sampleReading().copyWith(
        photos: [testPhoto('a'), testPhoto('b'), testPhoto('c')],
      );
      final session = ReadingPhotoSession(
        route: '/edit',
        repository: repo,
        store: store,
        readings: MemoryReadingRepository(),
        original: original,
      );
      final pending = store.pending = Completer<void>();
      final removing = session.removePhoto('a', {'value': '12'});
      expect(session.busy, true);
      await session.capture(ReadingSource.camera, formFields: {});
      await session.removePhoto('b', {});
      await session.reorderPhotos(['c', 'b'], {});
      expect(repo.captureCalls, 0);
      pending.complete();
      await removing;
      expect(session.busy, false);
      expect(session.photos.map((p) => p.id), ['b', 'c']);
      expect(repo.deleted, isEmpty);
    },
  );

  test(
    'failed replacement keeps the previous photo and cleans the new file',
    () async {
      final store = _ControlledStore()..failAtWrite = 2;
      final repo = _Photos();
      final session = ReadingPhotoSession(
        route: '/new',
        repository: repo,
        store: store,
        readings: MemoryReadingRepository(),
        original: sampleReading().copyWith(
          photos: [testPhoto('a'), testPhoto('b')],
        ),
      );
      await expectLater(
        session.capture(
          ReadingSource.camera,
          formFields: {'value': '12'},
          replacementId: 'a',
        ),
        throwsStateError,
      );
      expect(session.photos.map((p) => p.id), ['a', 'b']);
      expect(repo.deleted, ['/camera.jpg']);
      expect((await store.read('/new'))!['photos'], [
        testPhoto('a').toJson(),
        testPhoto('b').toJson(),
      ]);
      expect(await store.pendingRoute(), null);
    },
  );

  test(
    'closing while a draft is written does not resurrect deleted files',
    () async {
      final store = _ControlledStore();
      final repo = _Photos();
      final session = ReadingPhotoSession(
        route: '/new',
        repository: repo,
        store: store,
        readings: MemoryReadingRepository(),
      );
      await session.capture(ReadingSource.gallery, formFields: {});
      final pending = store.pending = Completer<void>();
      final removing = session.removePhoto(session.photos.first.id, {});
      await Future<void>.delayed(Duration.zero);
      final closing = session.close();
      await Future<void>.delayed(Duration.zero);
      pending.complete();
      await Future.wait([removing, closing]);
      expect(await store.read('/new'), null);
      expect(repo.deleted.toSet(), {'/gallery1.jpg', '/gallery2.jpg'});
    },
  );

  test(
    'reorder restores the draft and discard preserves saved files',
    () async {
      final original = sampleReading().copyWith(
        photos: [testPhoto('a'), testPhoto('b'), testPhoto('c')],
      );
      final store = MemoryPhotoDraftStore();
      final repo = _Photos();
      final readings = MemoryReadingRepository()..items[original.id] = original;
      ReadingPhotoSession makeSession() => ReadingPhotoSession(
        route: '/edit',
        repository: repo,
        store: store,
        readings: readings,
        original: original,
      );
      final session = makeSession();
      await session.reorderPhotos(
        ['c', 'a', 'b'],
        {'value': '35', 'note': 'Ärmel'},
      );
      expect(session.changed, true);
      expect(session.photos.map((p) => p.id), ['c', 'a', 'b']);
      final restored = makeSession();
      await restored.restore();
      expect(restored.photos.map((p) => p.id), ['c', 'a', 'b']);
      expect(restored.fields, {'value': '35', 'note': 'Ärmel'});
      await restored.discard();
      expect(restored.photos.map((p) => p.id), ['a', 'b', 'c']);
      expect(repo.deleted, isEmpty);
      for (final ids in [
        ['a', 'a', 'c'],
        ['a', 'b'],
        ['a', 'b', 'missing'],
      ]) {
        await expectLater(session.reorderPhotos(ids, {}), throwsArgumentError);
      }
      expect(session.photos.map((p) => p.id), ['c', 'a', 'b']);
    },
  );

  test(
    'failed reorder rolls back and unchanged order does not write',
    () async {
      final original = sampleReading().copyWith(
        photos: [testPhoto('a'), testPhoto('b')],
      );
      final session = ReadingPhotoSession(
        route: '/edit',
        repository: _Photos(),
        store: _FailingStore(),
        readings: MemoryReadingRepository(),
        original: original,
      );
      await session.reorderPhotos(['a', 'b'], {});
      await expectLater(
        session.reorderPhotos(['b', 'a'], {}),
        throwsStateError,
      );
      expect(session.photos.map((p) => p.id), ['a', 'b']);
      expect(session.changed, false);
      expect(session.busy, false);
    },
  );

  test('failed draft storage never launches the picker', () async {
    final repo = _Photos();
    final session = ReadingPhotoSession(
      route: '/new',
      repository: repo,
      store: _FailingStore(),
      readings: MemoryReadingRepository(),
    );
    await expectLater(
      session.capture(ReadingSource.camera, formFields: {'value': '5'}),
      throwsStateError,
    );
    expect(repo.captureCalls, 0);
    expect(session.photos, isEmpty);
    expect(session.busy, false);
  });

  test(
    'a completed photo-free reading cannot return as a stale draft',
    () async {
      final store = MemoryPhotoDraftStore();
      final readings = MemoryReadingRepository();
      final session = ReadingPhotoSession(
        route: '/new',
        repository: _Photos(),
        store: store,
        readings: readings,
      );
      await session.rememberFields({'value': '18'});
      readings.items[session.readingId] = sampleReading(
        id: session.readingId,
        source: ReadingSource.manual,
      );
      final recovered = ReadingPhotoSession(
        route: '/new',
        repository: _Photos(),
        store: store,
        readings: readings,
      );
      await recovered.restore();
      expect(recovered.fields, isEmpty);
      expect(await store.read('/new'), null);
    },
  );

  test(
    'mixed batches append, replace in place and discard only new files',
    () async {
      final repo = _Photos();
      final store = MemoryPhotoDraftStore();
      final original = sampleReading();
      final readings = MemoryReadingRepository()..items[original.id] = original;
      final session = ReadingPhotoSession(
        route: '/reading/reading/edit',
        repository: repo,
        store: store,
        readings: readings,
        original: original,
      );
      await session.capture(ReadingSource.gallery, formFields: {'value': '25'});
      expect(session.photos.map((p) => p.path), [
        '/synthetic.jpg',
        '/gallery1.jpg',
        '/gallery2.jpg',
      ]);
      final firstNewId = session.photos[1].id;
      await session.capture(
        ReadingSource.camera,
        formFields: {'value': '25'},
        replacementId: firstNewId,
      );
      expect(session.photos.map((p) => p.path), [
        '/synthetic.jpg',
        '/camera.jpg',
        '/gallery2.jpg',
      ]);
      expect(repo.deleted, ['/gallery1.jpg']);
      await session.removePhoto(session.photos.first.id, {'value': '25'});
      expect(repo.deleted, isNot(contains('/synthetic.jpg')));
      await session.discard();
      expect(repo.deleted.toSet(), {
        '/gallery1.jpg',
        '/camera.jpg',
        '/gallery2.jpg',
      });
      expect(await store.read(session.route), null);
    },
  );

  test(
    'recovery restores all gallery images, source, replacement and text fields',
    () async {
      final store = MemoryPhotoDraftStore();
      final original = sampleReading();
      final oldPhoto = original.currentPhotos.single;
      await store.write('/reading/reading/edit', {
        'originalUpdatedAt': original.updatedAt.toIso8601String(),
        'photos': [oldPhoto.toJson()],
        'ownedPaths': <String>[],
        'fields': {'value': '71', 'note': 'Mein Ärmel'},
        'pendingSource': 'gallery',
        'replacementId': oldPhoto.id,
      });
      expect(await store.pendingRoute(), '/reading/reading/edit');
      final repo = _Photos();
      final session = ReadingPhotoSession(
        route: '/reading/reading/edit',
        repository: repo,
        store: store,
        readings: MemoryReadingRepository()..items[original.id] = original,
        original: original,
      );
      await session.restore();
      expect(repo.recoveredSource, ReadingSource.gallery);
      expect(session.photos.map((p) => p.path), [
        '/gallery1.jpg',
        '/gallery2.jpg',
      ]);
      expect(session.fields, {'value': '71', 'note': 'Mein Ärmel'});
      expect(await store.pendingRoute(), null);
    },
  );

  test('another route cannot consume the pending picker result', () async {
    final repo = _Photos();
    final store = MemoryPhotoDraftStore();
    await store.write('/reading/other/edit', {'pendingSource': 'gallery'});
    final session = ReadingPhotoSession(
      route: '/reading/reading/edit',
      repository: repo,
      store: store,
      readings: MemoryReadingRepository(),
    );
    await session.restore();
    expect(repo.recoveredSource, null);
    expect(await store.pendingRoute(), '/reading/other/edit');
  });

  test('late capture results after closing are cleaned', () async {
    final pending = Completer<StoredMeterPhoto?>();
    final repo = _Photos()..pending = pending.future;
    final session = ReadingPhotoSession(
      route: '/new',
      repository: repo,
      store: MemoryPhotoDraftStore(),
      readings: MemoryReadingRepository(),
    );
    final capturing = session.capture(ReadingSource.camera, formFields: {});
    await Future<void>.delayed(Duration.zero);
    await session.close();
    pending.complete(_photo('late', ReadingSource.camera));
    await capturing;
    expect(repo.deleted, ['/late.jpg']);
  });

  test(
    'a stale draft after a successful commit never deletes saved photos',
    () async {
      final repo = _Photos();
      final store = MemoryPhotoDraftStore();
      final readings = MemoryReadingRepository();
      final session = ReadingPhotoSession(
        route: '/new',
        repository: repo,
        store: store,
        readings: readings,
      );
      await session.capture(ReadingSource.gallery, formFields: {});
      readings.items['saved'] = sampleReading(
        id: 'saved',
      ).copyWith(photos: List.of(session.photos));
      final recovered = ReadingPhotoSession(
        route: '/new',
        repository: repo,
        store: store,
        readings: readings,
      );
      await recovered.restore();
      expect(recovered.photos, isEmpty);
      expect(repo.deleted, isEmpty);
      expect(await store.read('/new'), null);
    },
  );
}

StoredMeterPhoto _photo(String name, ReadingSource source) => StoredMeterPhoto(
  path: '/$name.jpg',
  sha256: name.padRight(64, 'a'),
  source: source,
  capturedAt: DateTime.utc(2026, 9, 17),
);

class _Photos extends UnsupportedMeterPhotoCaptureRepository
    implements MultiPhotoCaptureRepository {
  final deleted = <String>[];
  ReadingSource? recoveredSource;
  Future<StoredMeterPhoto?>? pending;
  PhotoImportResult? batch;
  Completer<void>? pendingDelete;
  int captureCalls = 0;
  @override
  Future<StoredMeterPhoto?> capture(ReadingSource source) async {
    captureCalls++;
    return pending ?? Future.value(_photo('camera', source));
  }

  @override
  Future<PhotoImportResult> pickGalleryPhotos({
    PhotoImportProgress? onProgress,
  }) async =>
      batch ??
      PhotoImportResult(
        photos: [
          _photo('gallery1', ReadingSource.gallery),
          _photo('gallery2', ReadingSource.gallery),
        ],
      );
  @override
  Future<PhotoImportResult> recoverPhotos({
    required ReadingSource source,
    PhotoImportProgress? onProgress,
  }) async {
    recoveredSource = source;
    return pickGalleryPhotos();
  }

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    if (pendingDelete case final pending?) await pending.future;
  }
}

class _FailingStore extends MemoryPhotoDraftStore {
  @override
  Future<void> write(String route, Map<String, dynamic> draft) async =>
      throw StateError('Disk unavailable');
}

class _ControlledStore extends MemoryPhotoDraftStore {
  Completer<void>? pending;
  int? failAtWrite;
  int writes = 0;
  @override
  Future<void> write(String route, Map<String, dynamic> draft) async {
    final waiting = pending;
    pending = null;
    if (waiting != null) await waiting.future;
    if (++writes == failAtWrite) throw StateError('Disk unavailable');
    await super.write(route, draft);
  }
}
