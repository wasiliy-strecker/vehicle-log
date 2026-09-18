import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_detail_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_detail_screen.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

const _singleLabel = 'Fahrzeugprotokoll als PDF erstellen';
const _historyLabel = 'Fahrzeugprotokoll für den Fahrzeugverlauf erstellen';
final _photoOption = find.byKey(
  const ValueKey('evidence-photo-mode-currentPhotos'),
);
final _compactOption = find.byKey(
  const ValueKey('evidence-photo-mode-withoutPhotos'),
);

void main() {
  for (final hasPhotos in [false, true]) {
    testWidgets('single PDF uses only its own photos: $hasPhotos', (
      tester,
    ) async {
      final readings = _Readings();
      readings.items['reading'] = _reading(hasPhotos: hasPhotos);
      readings.items['other'] = _reading(id: 'other', hasPhotos: true);
      final reports = _Reports();
      await _open(tester, readings, reports, single: true);
      await _pressPdf(tester, single: true);
      expect(tester.widget<ListTile>(_photoOption).enabled, hasPhotos);
      if (!hasPhotos) {
        await tester.tap(_photoOption);
        await tester.pumpAndSettle();
        expect(
          find.text('Keine aktuellen Fotos oder PDFs vorhanden.'),
          findsOneWidget,
        );
        expect(reports.calls, 0);
      }
      await tester.tap(hasPhotos ? _photoOption : _compactOption);
      await tester.pumpAndSettle();
      expect(reports.calls, 1);
      expect(reports.selection!.single.id, 'reading');
      expect(
        reports.mode,
        hasPhotos
            ? EvidencePhotoMode.currentPhotos
            : EvidencePhotoMode.withoutPhotos,
      );
      expect(find.text('PDF-Vorschau'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'history checks all eleven entries and exports the same selection: $hasPhotos',
      (tester) async {
        final readings = _Readings();
        for (var index = 0; index < 11; index++) {
          readings.items['reading_$index'] =
              _reading(
                id: 'reading_$index',
                hasPhotos: hasPhotos && index == 10,
              ).copyWith(
                capturedAt: DateTime.utc(
                  2026,
                  9,
                  14,
                ).subtract(Duration(days: index)),
              );
        }
        final reports = _Reports();
        await _open(tester, readings, reports);
        expect(readings.lastPageLimit, 10);
        expect(readings.exportLoads, 0);
        await _pressPdf(tester);
        expect(readings.exportLoads, 1);
        expect(tester.widget<ListTile>(_photoOption).enabled, hasPhotos);
        if (!hasPhotos) {
          await tester.tap(_photoOption);
          await tester.pumpAndSettle();
          expect(reports.calls, 0);
          expect(find.text('PDF-Inhalt wählen'), findsOneWidget);
        }
        await tester.tap(hasPhotos ? _photoOption : _compactOption);
        await tester.pumpAndSettle();
        expect(reports.calls, 1);
        expect(reports.selection, hasLength(11));
        expect(identical(reports.selection, readings.lastSelection), isTrue);
        expect(readings.exportLoads, 1);
        expect(
          reports.mode,
          hasPhotos
              ? EvidencePhotoMode.currentPhotos
              : EvidencePhotoMode.withoutPhotos,
        );
        expect(find.text('PDF-Vorschau'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'load failure and cancellation allow retry with refreshed photos',
    (tester) async {
      final readings = _Readings()..failNext = true;
      readings.items['reading'] = _reading();
      final reports = _Reports();
      await _open(tester, readings, reports);
      await _pressPdf(tester);
      expect(
        find.textContaining('PDF konnte nicht erstellt werden:'),
        findsOneWidget,
      );
      expect(find.text('PDF-Inhalt wählen'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, _historyLabel),
            )
            .onPressed,
        isNotNull,
      );
      await _pressPdf(tester);
      expect(tester.widget<ListTile>(_photoOption).enabled, isFalse);
      await _cancelSheet(tester);
      readings.items['reading'] = _reading(hasPhotos: true);
      await _pressPdf(tester);
      expect(tester.widget<ListTile>(_photoOption).enabled, isTrue);
      await _cancelSheet(tester);
      readings.items['reading'] = _reading();
      await _pressPdf(tester);
      expect(tester.widget<ListTile>(_photoOption).enabled, isFalse);
      expect(readings.exportLoads, 4);
      expect(reports.calls, 0);
      await tester.tap(_compactOption);
      await tester.pumpAndSettle();
      expect(reports.calls, 1);
      expect(find.text('PDF-Vorschau'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history preparation blocks repeated taps and releases after cancellation',
    (tester) async {
      final readings = _Readings()..pending = Completer<List<MeterReading>>();
      readings.items['reading'] = _reading();
      await _open(tester, readings, _Reports());
      final button = find.widgetWithText(FilledButton, _historyLabel);
      await tester.ensureVisible(button);
      final start = tester.widget<FilledButton>(button).onPressed!;
      start();
      start();
      await tester.pump();
      expect(readings.exportLoads, 1);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.text('PDF-Inhalt wählen'), findsNothing);
      readings.pending!.complete(readings.items.values.toList());
      await tester.pumpAndSettle();
      await _cancelSheet(tester);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}

MeterReading _reading({String id = 'reading', bool hasPhotos = false}) =>
    sampleReading(
      id: id,
      source: hasPhotos ? ReadingSource.camera : ReadingSource.manual,
    );

Future<void> _open(
  WidgetTester tester,
  _Readings readings,
  _Reports reports, {
  bool single = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final meter = sampleBook();
  final router = GoRouter(
    initialLocation: single ? '/reading' : '/meter',
    routes: [
      GoRoute(path: '/', name: 'home', builder: (_, _) => const Scaffold()),
      GoRoute(
        path: '/meter',
        builder: (_, _) => MeterDetailScreen(meterId: meter.id),
      ),
      GoRoute(
        path: '/reading',
        builder: (_, _) => const ReadingDetailScreen(readingId: 'reading'),
      ),
      GoRoute(
        path: '/preview',
        name: 'evidencePreview',
        builder: (_, _) => const Scaffold(body: Text('PDF-Vorschau')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        meterRepositoryProvider.overrideWithValue(
          MemoryMeterRepository()..items[meter.id] = meter,
        ),
        meterReadingRepositoryProvider.overrideWithValue(readings),
        evidenceExportRepositoryProvider.overrideWithValue(
          MemoryEvidenceExportRepository(),
        ),
        meterReminderRepositoryProvider.overrideWithValue(
          NoopMeterReminderRepository(),
        ),
        evidenceReportServiceProvider.overrideWithValue(reports),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pressPdf(WidgetTester tester, {bool single = false}) async {
  final target = find.widgetWithText(
    FilledButton,
    single ? _singleLabel : _historyLabel,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _cancelSheet(WidgetTester tester) async {
  Navigator.of(tester.element(_photoOption)).pop();
  await tester.pumpAndSettle();
}

class _Readings extends MemoryReadingRepository {
  int exportLoads = 0;
  bool failNext = false;
  Completer<List<MeterReading>>? pending;
  List<MeterReading>? lastSelection;

  @override
  Future<List<MeterReading>> loadForMeter(String meterId) async {
    exportLoads++;
    if (failNext) {
      failNext = false;
      throw StateError('Synthetic load failure');
    }
    return lastSelection =
        await (pending?.future ?? super.loadForMeter(meterId));
  }
}

class _Reports extends EvidenceReportService {
  _Reports() : super(exports: MemoryEvidenceExportRepository());
  int calls = 0;
  EvidencePhotoMode? mode;
  List<MeterReading>? selection;

  @override
  Future<GeneratedEvidenceReport> createSingle({
    required MeterReading reading,
    required List<ReadingRevision> revisions,
    EvidencePhotoMode photoMode = EvidencePhotoMode.allPhotos,
  }) async => _report([reading], photoMode, EvidenceExportKind.singleReading);

  @override
  Future<GeneratedEvidenceReport> createHistory({
    required Meter meter,
    required List<MeterReading> readings,
    required Map<String, List<ReadingRevision>> revisions,
    EvidencePhotoMode photoMode = EvidencePhotoMode.allPhotos,
  }) async => _report(readings, photoMode, EvidenceExportKind.meterHistory);

  GeneratedEvidenceReport _report(
    List<MeterReading> readings,
    EvidencePhotoMode photoMode,
    EvidenceExportKind kind,
  ) {
    calls++;
    mode = photoMode;
    selection = readings;
    return GeneratedEvidenceReport(
      bytes: Uint8List(0),
      record: EvidenceExportRecord(
        id: 'report',
        meterId: readings.first.meterId,
        kind: kind,
        readingIds: readings.map((reading) => reading.id).toList(),
        createdAt: DateTime.utc(2026),
        fileName: 'synthetic.pdf',
        filePath: '/synthetic.pdf',
        pdfSha256: 'hash',
        manifestSha256: 'hash',
        photoMode: photoMode,
      ),
    );
  }
}
