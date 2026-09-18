import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/document_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/files/photo_draft_store.dart';
import 'package:fahrzeugakte/features/meters/application/reading_photo_session.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

ReadingDocument _document(String id) => ReadingDocument(
  id: id,
  fileName: '$id.pdf',
  path: '/synthetic/$id.pdf',
  sha256: 'a' * 64,
  pageCount: 2,
  sizeBytes: 20,
  source: DocumentSource.imported,
  addedAt: DateTime.utc(2026),
);

class _Documents implements DocumentRepository {
  final deleted = <String>[];
  DocumentImportResult next = const DocumentImportResult();
  Future<void> Function()? before;
  Future<void> Function(String)? onDelete;
  @override
  Future<DocumentImportResult> pick({bool multiple = true}) async {
    await before?.call();
    return next;
  }

  @override
  Future<DocumentImportResult> scan() => pick();
  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    await onDelete?.call(path);
  }
}

void main() {
  test(
    'interrupted scanner restores inputs and existing PDFs without relaunching',
    () async {
      final store = MemoryPhotoDraftStore();
      final documents = _Documents();
      final readings = MemoryReadingRepository();
      final session = ReadingPhotoSession(
        route: '/meter/vehicle/capture',
        repository: const UnsupportedMeterPhotoCaptureRepository(),
        documentRepository: documents,
        store: store,
        readings: readings,
      );
      documents.next = DocumentImportResult(
        documents: [_document('before-scan')],
      );
      await session.captureDocuments(
        scan: false,
        formFields: {'cost': '19,90', 'workshop': 'Werkstatt'},
      );
      final draft = Map<String, dynamic>.of((await store.read(session.route))!);
      draft['pendingDocument'] = true;
      await store.write(session.route, draft);
      documents.before = () async =>
          fail('Recovery must not reopen the scanner');
      final restored = ReadingPhotoSession(
        route: session.route,
        repository: const UnsupportedMeterPhotoCaptureRepository(),
        documentRepository: documents,
        store: store,
        readings: readings,
      );
      await restored.restore();
      expect(restored.fields['cost'], '19,90');
      expect(restored.documents.single.id, 'before-scan');
      expect(await store.pendingRoute(), isNull);
      await restored.close();
      expect(documents.deleted, ['/synthetic/before-scan.pdf']);
    },
  );

  test('closing during PDF cleanup deletes each owned file once', () async {
    final documents = _Documents();
    final session = ReadingPhotoSession(
      route: '/meter/vehicle/capture',
      repository: const UnsupportedMeterPhotoCaptureRepository(),
      documentRepository: documents,
      store: MemoryPhotoDraftStore(),
      readings: MemoryReadingRepository(),
    );
    documents.next = DocumentImportResult(
      documents: [_document('first'), _document('second')],
    );
    await session.captureDocuments(scan: false, formFields: {});
    final started = Completer<void>();
    final finish = Completer<void>();
    documents.onDelete = (path) async {
      if (path.endsWith('/first.pdf')) {
        started.complete();
        await finish.future;
      }
    };
    final removal = session.changeDocuments([session.documents.last], {});
    await started.future;
    final close = session.close();
    finish.complete();
    await Future.wait([removal, close]);
    expect(documents.deleted, [
      '/synthetic/first.pdf',
      '/synthetic/second.pdf',
    ]);
  });

  test(
    'PDF picker persists all fields and replacement drafts never delete originals',
    () async {
      final store = MemoryPhotoDraftStore();
      final documents = _Documents();
      final originalDoc = _document('saved');
      final original = sampleReading(
        source: ReadingSource.manual,
      ).copyWith(documents: [originalDoc]);
      final readings = MemoryReadingRepository()..items[original.id] = original;
      final session = ReadingPhotoSession(
        route: '/reading/${original.id}/edit',
        repository: const UnsupportedMeterPhotoCaptureRepository(),
        documentRepository: documents,
        store: store,
        readings: readings,
        original: original,
      );
      documents.before = () async {
        final draft = (await store.read(session.route))!;
        expect(draft['pendingDocument'], isTrue);
        expect(await store.pendingRoute(), session.route);
        expect((draft['fields'] as Map)['cost'], '249,90');
        expect((draft['documents'] as List).single['id'], 'saved');
      };
      documents.next = DocumentImportResult(
        documents: [_document('replacement')],
      );
      await session.captureDocuments(
        scan: false,
        replacementId: 'saved',
        formFields: {
          'activityText': 'Reparatur',
          'workshop': 'Werkstatt',
          'cost': '249,90',
        },
      );
      expect(session.documents.single.id, 'replacement');
      expect(session.changed, isTrue);
      final recovered = ReadingPhotoSession(
        route: session.route,
        repository: const UnsupportedMeterPhotoCaptureRepository(),
        documentRepository: documents,
        store: store,
        readings: readings,
        original: original,
      );
      await recovered.restore();
      expect(recovered.documents.single.id, 'replacement');
      expect(recovered.fields['workshop'], 'Werkstatt');
      await recovered.discard();
      expect(documents.deleted, ['/synthetic/replacement.pdf']);
      expect(recovered.documents.single.id, 'saved');
      expect(await store.read(session.route), isNull);
    },
  );

  test(
    'cancel, reorder, remove and commit preserve document ownership',
    () async {
      final store = MemoryPhotoDraftStore();
      final documents = _Documents();
      final readings = MemoryReadingRepository();
      final session = ReadingPhotoSession(
        route: '/meter/vehicle/capture',
        repository: const UnsupportedMeterPhotoCaptureRepository(),
        documentRepository: documents,
        store: store,
        readings: readings,
      );
      documents.next = DocumentImportResult(
        documents: [_document('first'), _document('second')],
      );
      await session.captureDocuments(scan: false, formFields: {'cost': ''});
      await session.changeDocuments(session.documents.reversed.toList(), {});
      expect(session.documents.map((d) => d.id), ['second', 'first']);
      documents.next = const DocumentImportResult();
      await session.captureDocuments(
        scan: true,
        formFields: {'workshop': 'keep'},
      );
      expect(session.documents, hasLength(2));
      await session.changeDocuments([session.documents.first], session.fields);
      expect(documents.deleted, ['/synthetic/first.pdf']);
      await session.committed();
      await session.close();
      expect(documents.deleted, ['/synthetic/first.pdf']);
      expect(await store.read(session.route), isNull);
    },
  );
}
