import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/files/photo_draft_store.dart';
import 'package:fahrzeugakte/features/meters/application/reading_photo_session.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_documents.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

const _hint = 'Zum Sortieren eine PDF länger gedrückt halten und verschieben.';

void main() {
  testWidgets('PDF drag updates the correction draft and survives recovery', (
    tester,
  ) async {
    final session = _session(4);
    await _mount(tester, session);
    expect(find.text(_hint), findsOneWidget);
    await _drag(tester, 'a', 'c');
    expect(_ids(session), ['b', 'c', 'a', 'd']);
    await _drag(tester, 'd', 'b');
    expect(_ids(session), ['d', 'b', 'c', 'a']);
    expect(session.original!.documents.map((d) => d.id), ['a', 'b', 'c', 'd']);

    final recovered = ReadingPhotoSession(
      route: session.route,
      repository: session.repository,
      store: session.store,
      readings: session.readings,
      original: session.original,
    );
    await recovered.restore();
    expect(_ids(recovered), ['d', 'b', 'c', 'a']);
    expect(recovered.fields['workshop'], 'Musterwerkstatt');
    recovered.dispose();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('document-drag-d'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(const Offset(-40, 250));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_ids(session), ['d', 'b', 'c', 'a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu sorting works and becoming busy blocks a pending drop', (
    tester,
  ) async {
    final session = _session(3);
    await _mount(tester, session, textScale: 1.8);
    await tester.tap(find.byKey(const ValueKey('document-menu-a')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'Nach vorne'),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('Nach hinten'));
    await tester.pumpAndSettle();
    expect(_ids(session), ['b', 'a', 'c']);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('document-drag-b'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    session.busy = true;
    session.notifyListeners();
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('document-drag-c'))),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_ids(session), ['b', 'a', 'c']);
    expect(
      tester
          .widget<LongPressDraggable<String>>(
            find.byKey(const ValueKey('document-drag-b')),
          )
          .maxSimultaneousDrags,
      0,
    );
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    session.busy = false;
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty, single and read-only PDF lists offer no drag sorting', (
    tester,
  ) async {
    final session = _session(1);
    await _mount(tester, session);
    expect(find.text(_hint), findsNothing);
    expect(find.byType(LongPressDraggable<String>), findsNothing);
    session.documents.clear();
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Keine aktuellen PDFs'), findsOneWidget);
    expect(find.text(_hint), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingDocuments(documents: [_document('a'), _document('b')]),
        ),
      ),
    );
    expect(find.byType(LongPressDraggable<String>), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets(
    'PDF dragging scrolls the form and cancellation stops scrolling',
    (tester) async {
      final session = _session(16);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _mount(tester, session, height: 600, scroll: scroll);
      final original = _ids(session).toList();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('document-drag-a'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(const Offset(180, 590));
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, greaterThan(200));
      await gesture.moveTo(const Offset(-40, 300));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_ids(session), original);
      final stoppedAt = scroll.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, stoppedAt);
      expect(tester.takeException(), isNull);
    },
  );
}

ReadingDocument _document(String id) => ReadingDocument(
  id: id,
  fileName: 'Beleg-$id.pdf',
  path: '/synthetic/$id.pdf',
  sha256: 'a' * 64,
  pageCount: 2,
  sizeBytes: 20,
  source: DocumentSource.imported,
  addedAt: DateTime.utc(2026),
);

ReadingPhotoSession _session(int count) {
  final original = sampleReading(source: ReadingSource.manual).copyWith(
    documents: List.generate(
      count,
      (index) => _document(String.fromCharCode(97 + index)),
    ),
  );
  return ReadingPhotoSession(
    route: '/reading/${original.id}/edit',
    repository: const UnsupportedMeterPhotoCaptureRepository(),
    store: MemoryPhotoDraftStore(),
    readings: MemoryReadingRepository()..items[original.id] = original,
    original: original,
  );
}

Iterable<String> _ids(ReadingPhotoSession session) =>
    session.documents.map((document) => document.id);

Future<void> _drag(WidgetTester tester, String from, String to) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(ValueKey('document-drag-$from'))),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(
    tester.getCenter(find.byKey(ValueKey('document-drag-$to'))),
  );
  await tester.pump(const Duration(milliseconds: 150));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  ReadingPhotoSession session, {
  double height = 1000,
  double textScale = 1,
  ScrollController? scroll,
}) async {
  await tester.binding.setSurfaceSize(Size(360, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          controller: scroll,
          children: [
            ListenableBuilder(
              listenable: session,
              builder: (_, _) => ReadingDocumentEditor(
                session: session,
                fields: () => {'workshop': 'Musterwerkstatt'},
              ),
            ),
            const SizedBox(height: 200),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
