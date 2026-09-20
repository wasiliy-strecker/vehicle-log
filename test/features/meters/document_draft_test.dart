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
  final multipleSelections = <bool>[];
  final budgets = <DocumentImportBudget>[];
  DocumentImportResult next = const DocumentImportResult();
  Future<void> Function()? before;
  Future<void> Function(String)? onDelete;
  @override
  Future<DocumentImportResult> pick({
    bool multiple = true,
    DocumentImportBudget budget = const DocumentImportBudget(),
  }) async {
    multipleSelections.add(multiple);
    budgets.add(budget);
    await before?.call();
    return next;
  }

  @override
  Future<DocumentImportResult> scan({
    DocumentImportBudget budget = const DocumentImportBudget(),
  }) => pick(budget: budget);
  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    await onDelete?.call(path);
  }
}

class _FailingDraftStore extends MemoryPhotoDraftStore {
  int writes = 0;
  int? failAt;
  @override
  Future<void> write(String route, Map<String, dynamic> draft) async {
    writes++;
    if (writes == failAt) throw StateError('Synthetic draft write failure');
    await super.write(route, draft);
  }
}

void main() {
  ReadingDocument pages(String id, int count) =>
      ReadingDocument.fromJson({..._document(id).toJson(), 'pageCount': count});
  ReadingPhotoSession sessionWith(
    List<ReadingDocument> documents,
    _Documents repository,
  ) {
    final original = sampleReading(
      source: ReadingSource.manual,
    ).copyWith(documents: documents);
    return ReadingPhotoSession(
      route: '/reading/reading/edit',
      original: original,
      repository: const UnsupportedMeterPhotoCaptureRepository(),
      documentRepository: repository,
      store: MemoryPhotoDraftStore(),
      readings: MemoryReadingRepository()..items[original.id] = original,
    );
  }

  test(
    'remaining pages reach the scanner and rejected selections leave no files',
    () async {
      final repository = _Documents()
        ..next = DocumentImportResult(
          documents: [pages('accepted', 8), pages('rejected', 1)],
        );
      final session = sessionWith([pages('old', 12)], repository);
      final result = await session.captureDocuments(scan: true, formFields: {});
      expect(repository.budgets.single.pages, 8);
      expect(session.documentPages, 20);
      expect(result.failures, hasLength(1));
      expect(repository.deleted, ['/synthetic/rejected.pdf']);
      await session.discard();
      expect(repository.deleted, contains('/synthetic/accepted.pdf'));
      expect(repository.deleted, isNot(contains('/synthetic/old.pdf')));
    },
  );
  test(
    'replacement receives its own pages back and legacy entries can shrink',
    () async {
      final repository = _Documents()
        ..next = DocumentImportResult(documents: [pages('replacement', 10)]);
      final session = sessionWith([pages('legacy', 30)], repository);
      expect(session.documentBudget().exhausted, isTrue);
      await session.captureDocuments(
        scan: false,
        replacementId: 'legacy',
        formFields: {},
      );
      expect(repository.budgets.single.pages, 30);
      expect(session.documentPages, 10);
      expect(repository.deleted, isEmpty);
      await session.discard();
      expect(session.documentPages, 30);
      expect(repository.deleted, ['/synthetic/replacement.pdf']);
    },
  );

  test(
    'failed import persistence keeps originals and removes only new files',
    () async {
      final store = _FailingDraftStore()..failAt = 2;
      final repository = _Documents()
        ..next = DocumentImportResult(documents: [_document('new')]);
      final original = sampleReading(
        source: ReadingSource.manual,
      ).copyWith(documents: [_document('saved')]);
      final readings = MemoryReadingRepository()..items[original.id] = original;
      final session = ReadingPhotoSession(
        route: '/reading/${original.id}/edit',
        original: original,
        repository: const UnsupportedMeterPhotoCaptureRepository(),
        documentRepository: repository,
        store: store,
        readings: readings,
      );
      await expectLater(
        session.captureDocuments(
          scan: false,
          replacementId: 'saved',
          formFields: {'cost': '99,90'},
        ),
        throwsStateError,
      );
      expect(session.documents.single.id, 'saved');
      expect(repository.deleted, ['/synthetic/new.pdf']);
      expect(session.busy, isFalse);
      final recovered = ReadingPhotoSession(
        route: session.route,
        original: original,
        repository: const UnsupportedMeterPhotoCaptureRepository(),
        documentRepository: repository,
        store: store,
        readings: readings,
      );
      await recovered.restore();
      expect(recovered.documents.single.id, 'saved');
      expect(recovered.fields['cost'], '99,90');
    },
  );

  test('failed reorder or removal restores the durable PDF draft', () async {
    for (final remove in [false, true]) {
      final store = _FailingDraftStore();
      final repository = _Documents()
        ..next = DocumentImportResult(
          documents: [_document('a'), _document('b')],
        );
      final session = ReadingPhotoSession(
        route: '/meter/vehicle/capture',
        repository: const UnsupportedMeterPhotoCaptureRepository(),
        documentRepository: repository,
        store: store,
        readings: MemoryReadingRepository(),
      );
      await session.captureDocuments(scan: false, formFields: {});
      store.failAt = store.writes + 1;
      await expectLater(
        session.changeDocuments(
          remove
              ? [session.documents.last]
              : session.documents.reversed.toList(),
          {},
        ),
        throwsStateError,
      );
      expect(session.documents.map((d) => d.id), ['a', 'b']);
      expect(repository.deleted, isEmpty);
      final saved = (await store.read(session.route))!['documents'] as List;
      expect(saved.map((d) => d['id']), ['a', 'b']);
      expect(session.busy, isFalse);
    }
  });
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
      expect(documents.multipleSelections, [false]);
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
      expect(documents.multipleSelections, [true]);
      expect(session.documents.map((d) => d.id), ['first', 'second']);
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
