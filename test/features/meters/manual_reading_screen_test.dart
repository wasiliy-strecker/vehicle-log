import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/ocr/meter_ocr_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/capture_reading_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/edit_reading_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_detail_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_history_tile.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  testWidgets(
    'new activity is empty and required, custom text saves and corrects',
    (tester) async {
      final readings = MemoryReadingRepository();
      await _open(tester, readings, _Photos(), _Ocr());
      await _press(tester, 'Ohne Foto erfassen');
      final activity = find.byKey(const ValueKey('care-activity'));
      expect(tester.widget<TextFormField>(activity).controller!.text, isEmpty);
      await _press(tester, 'Eintrag speichern');
      expect(find.text('Bitte eine Aktivität angeben.'), findsOneWidget);
      expect(readings.items, isEmpty);
      await tester.ensureVisible(activity);
      await tester.enterText(activity, '   Erste Blüte   ');
      await _press(tester, 'Eintrag speichern');
      await _settleSave(tester, () => readings.items.isNotEmpty);
      final saved = readings.items.values.single;
      expect(saved.activity, CareActivity.custom);
      expect(saved.activityLabel, 'Erste Blüte');
      expect(saved.hasMeasurement, isFalse);
      expect(saved.hasPhoto, isFalse);
      expect(find.text('Erste Blüte'), findsOneWidget);
      expect(find.text('Fotos sortieren'), findsNothing);
      await _press(tester, 'Bearbeiten');
      expect(
        tester.widget<TextFormField>(activity).controller!.text,
        'Erste Blüte',
      );
      await tester.ensureVisible(activity);
      await tester.enterText(activity, 'Blätter besprüht');
      await _press(tester, 'Änderungen speichern');
      await _settleSave(
        tester,
        () => readings.items.values.single.activityLabel == 'Blätter besprüht',
      );
      expect(await readings.loadRevisions(saved.id), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved custom activities are selectable across plants', (
    tester,
  ) async {
    final readings = MemoryReadingRepository();
    readings.items['other'] =
        sampleReading(
          id: 'other',
          book: sampleBook(id: 'otherPlant'),
        ).copyWith(
          activity: CareActivity.custom,
          customActivityLabel: 'Tachotausch',
        );
    await _open(tester, readings, _Photos(), _Ocr());
    await _press(tester, 'Ohne Foto erfassen');
    final activity = find.byKey(const ValueKey('care-activity'));
    await tester.enterText(activity, 'tacho');
    await tester.pumpAndSettle();
    expect(find.text('Wartung'), findsNothing);
    await tester.tap(find.text('Tachotausch'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(activity).controller!.text,
      'Tachotausch',
    );
    await _press(tester, 'Eintrag speichern');
    await _settleSave(tester, () => readings.items.length == 2);
    expect(
      readings.items.values.singleWhere((r) => r.id != 'other').activityLabel,
      'Tachotausch',
    );
    expect(tester.takeException(), isNull);
  });

  for (final activity in CareActivity.presets) {
    testWidgets('saves ${activity.label} without a measurement or photo', (
      tester,
    ) async {
      final readings = MemoryReadingRepository();
      await _open(tester, readings, _Photos(), _Ocr());
      await _press(tester, 'Ohne Foto erfassen');
      await tester.tap(find.byKey(const ValueKey('care-activity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(activity.label).last);
      await tester.pumpAndSettle();
      await _press(tester, 'Eintrag speichern');
      await _settleSave(tester, () => readings.items.isNotEmpty);
      final saved = readings.items.values.single;
      expect(saved.activity, activity);
      expect(saved.hasMeasurement, isFalse);
      expect(saved.hasPhoto, isFalse);
      expect(find.text(activity.label), findsOneWidget);
      expect(find.textContaining('0 km'), findsNothing);
      await _press(tester, 'Bearbeiten');
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Kilometerstand (optional)'),
            )
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kilometerstand (optional)'),
        '32',
      );
      await _press(tester, 'Änderungen speichern');
      await _settleSave(
        tester,
        () => readings.items.values.single.hasMeasurement,
      );
      expect(readings.items.values.single.activity, activity);
      expect(readings.items.values.single.value.displayText, '32');
      expect(tester.takeException(), isNull);
    });
  }
  for (final manual in [false, true]) {
    testWidgets('future reading saves and corrects directly, manual=$manual', (
      tester,
    ) async {
      final readings = MemoryReadingRepository();
      await _open(tester, readings, _Photos(), _Ocr());
      await _press(
        tester,
        manual ? 'Ohne Foto erfassen' : 'Fahrzeug fotografieren',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kilometerstand (optional)'),
        '150',
      );
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'Kilometerstand',
      );
      final selected = DateTime(2100, 1, 1, 12, 30);
      await _chooseTime(tester, selected);
      expect(find.textContaining('Zukunft'), findsNothing);
      await _press(
        tester,
        manual ? 'Eintrag speichern' : 'Eintrag bestätigen und speichern',
      );
      expect(find.text('Zukünftigen Zeitpunkt speichern?'), findsNothing);
      await _settleSave(tester, () => readings.items.isNotEmpty);
      expect(find.text('Fahrzeugeintrag gespeichert.'), findsOneWidget);
      final created = readings.items.values.single;
      expect(created.capturedAt, selected.toUtc());
      expect(created.storedAt.isBefore(created.capturedAt), isTrue);
      expect(
        created.source,
        manual ? ReadingSource.manual : ReadingSource.camera,
      );
      expect(find.textContaining('Zukunft'), findsNothing);

      await _press(tester, 'Bearbeiten');
      await _press(tester, 'Änderungen speichern');
      await _settleSave(
        tester,
        () => find.text('Keine Änderungen vorhanden.').evaluate().isNotEmpty,
      );
      expect(readings.revisions, isEmpty);
      expect(find.text('Keine Änderungen vorhanden.'), findsOneWidget);
      expect(find.text('Änderungen gespeichert.'), findsNothing);

      await _press(tester, 'Bearbeiten');
      final corrected = DateTime(2100, 1, 2, 13, 45);
      await _chooseTime(tester, corrected);
      expect(find.textContaining('Zukunft'), findsNothing);
      await _press(tester, 'Änderungen speichern');
      expect(find.text('Zukünftigen Zeitpunkt speichern?'), findsNothing);
      await _settleSave(
        tester,
        () => readings.items.values.single.capturedAt == corrected.toUtc(),
      );
      expect(find.text('Änderungen gespeichert.'), findsOneWidget);
      final saved = readings.items.values.single;
      expect(saved.capturedAt, corrected.toUtc());
      expect(saved.storedAt, created.storedAt);
      expect(await readings.loadRevisions(saved.id), isEmpty);
      expect(find.textContaining('Zukunft'), findsNothing);
    });
  }

  testWidgets(
    'manual action saves a plain reading, edits it and accepts a first photo',
    (tester) async {
      final readings = MemoryReadingRepository();
      final photos = _Photos();
      final ocr = _Ocr();
      await _open(tester, readings, photos, ocr);
      final manual = find.widgetWithText(FilledButton, 'Ohne Foto erfassen');
      await tester.ensureVisible(manual);
      expect(
        tester.getTopLeft(manual).dy,
        lessThan(
          tester
              .getTopLeft(
                find.widgetWithText(OutlinedButton, 'Fotos aus Galerie'),
              )
              .dy,
        ),
      );
      await tester.tap(manual);
      await tester.pumpAndSettle();
      expect(find.text('Veränderungen festhalten'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Kein sicherer Wert erkannt'), findsNothing);
      expect(find.text('km'), findsWidgets);
      expect(find.text('Datum & Uhrzeit ändern'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'Kilometerstand',
      );
      final value = find.widgetWithText(
        TextFormField,
        'Kilometerstand (optional)',
      );
      await tester.enterText(value, '12-13');
      await _press(tester, 'Eintrag speichern');
      expect(find.text('Bitte eine ganze Zahl ab 0 eingeben.'), findsOneWidget);
      expect(readings.items, isEmpty);
      await tester.enterText(value, '130');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notiz'),
        'Kapitel abgeschlossen',
      );
      await _press(tester, 'Eintrag speichern');
      await _settleSave(tester, () => readings.items.isNotEmpty);
      var saved = readings.items.values.single;
      expect(saved.source, ReadingSource.manual);
      expect(saved.value.displayText, '130');
      expect(saved.note, 'Kapitel abgeschlossen');
      expect(find.text('Manuell erfasst'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(photos.captures, 0);
      expect(ocr.calls, 0);
      expect(photos.deleted, isEmpty);

      await _press(tester, 'Bearbeiten');
      expect(find.byType(Image), findsNothing);
      expect(find.text('Fotos aus Galerie hinzufügen'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kilometerstand (optional)'),
        '135',
      );
      await _press(tester, 'Änderungen speichern');
      await _settleSave(
        tester,
        () => readings.items.values.single.value.displayText == '135',
      );
      saved = readings.items.values.single;
      expect(saved.hasPhoto, isFalse);
      expect(await readings.loadRevisions(saved.id), isEmpty);

      await _press(tester, 'Bearbeiten');
      await _press(tester, 'Fotos aus Galerie hinzufügen');
      expect(
        find.text('Das bisherige Foto bleibt als frühere Version erhalten.'),
        findsNothing,
      );
      await _press(tester, 'Änderungen speichern');
      await _settleSave(tester, () => readings.items.values.single.hasPhoto);
      saved = readings.items.values.single;
      expect(saved.source, ReadingSource.gallery);
      expect(saved.photoHistory, isEmpty);
      expect(photos.captures, 1);
      expect(ocr.calls, 0);
      expect(photos.deleted, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual back returns to choices and protects unsaved changes', (
    tester,
  ) async {
    final readings = MemoryReadingRepository();
    final photos = _Photos();
    final ocr = _Ocr();
    await _open(tester, readings, photos, ocr);
    await _press(tester, 'Ohne Foto erfassen');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Ohne Foto erfassen'), findsOneWidget);
    expect(find.text('Eintrag verwerfen?'), findsNothing);
    await _press(tester, 'Ohne Foto erfassen');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kilometerstand (optional)'),
      '85',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag verwerfen?'), findsOneWidget);
    await _press(tester, 'Weiter bearbeiten');
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Kilometerstand (optional)'),
          )
          .controller!
          .text,
      '85',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _press(tester, 'Eintrag verwerfen');
    expect(find.text('Ohne Foto erfassen'), findsOneWidget);
    expect(readings.items, isEmpty);
    expect(photos.captures, 0);
    expect(ocr.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual history entries show progress and an entry icon instead of a missing photo',
    (tester) async {
      final manual = sampleReading(source: ReadingSource.manual, value: '130');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadingHistoryTile(
              reading: manual,
              previous: sampleReading(value: '85'),
              showDelta: true,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('85 → 130 = 45 km Differenz'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note_outlined), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.byType(Image), findsNothing);
    },
  );
}

Future<GoRouter> _open(
  WidgetTester tester,
  MemoryReadingRepository readings,
  _Photos photos,
  _Ocr ocr,
) async {
  await tester.binding.setSurfaceSize(const Size(430, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final book = sampleBook();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => CaptureReadingScreen(meterId: book.id),
      ),
      GoRoute(
        path: '/reading/:id',
        name: 'readingDetail',
        builder: (_, state) =>
            ReadingDetailScreen(readingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/edit/:id',
        name: 'readingEdit',
        builder: (_, state) =>
            EditReadingScreen(readingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/book/:id',
        name: 'meterDetail',
        builder: (_, _) => const Scaffold(body: Text('Fahrzeugeübersicht')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        meterRepositoryProvider.overrideWithValue(
          MemoryMeterRepository()..items[book.id] = book,
        ),
        meterReadingRepositoryProvider.overrideWithValue(readings),
        evidenceExportRepositoryProvider.overrideWithValue(
          MemoryEvidenceExportRepository(),
        ),
        evidencePhotoAssetRepositoryProvider.overrideWithValue(
          const NoopEvidencePhotoAssetRepository(),
        ),
        meterReminderRepositoryProvider.overrideWithValue(
          NoopMeterReminderRepository(),
        ),
        meterPhotoCaptureRepositoryProvider.overrideWithValue(photos),
        meterOcrRepositoryProvider.overrideWithValue(ocr),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _press(WidgetTester tester, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final target = find.text(text);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  ScaffoldMessenger.of(tester.element(target)).clearSnackBars();
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
  // Saving also includes asynchronous hashing; settle those separately.
  if (text != 'Eintrag speichern' && text != 'Änderungen speichern') {
    await tester.pumpAndSettle();
  }
}

Future<void> _settleSave(WidgetTester tester, bool Function() saved) async {
  for (var attempt = 0; attempt < 50 && !saved(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _Photos extends UnsupportedMeterPhotoCaptureRepository {
  var captures = 0;
  final deleted = <String>[];
  @override
  Future<StoredMeterPhoto?> capture(ReadingSource source) async {
    captures++;
    return StoredMeterPhoto(
      path: '/synthetic-added.jpg',
      sha256: 'b' * 64,
      source: source,
      capturedAt: DateTime.utc(2026, 9, 15),
    );
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

class _Ocr implements MeterOcrRepository {
  var calls = 0;
  @override
  Future<MeterOcrResult> recognize(String photoPath) async {
    calls++;
    return const MeterOcrResult(rawText: '', candidates: [], confidence: 0);
  }
}

Future<void> _chooseTime(WidgetTester tester, DateTime selected) async {
  await _press(tester, 'Datum & Uhrzeit ändern');
  // Supply the picker results; exercise the real form/save flow with that date.
  Navigator.of(tester.element(find.byType(DatePickerDialog))).pop(selected);
  await tester.pumpAndSettle();
  Navigator.of(
    tester.element(find.byType(TimePickerDialog)),
  ).pop(TimeOfDay.fromDateTime(selected));
  await tester.pumpAndSettle();
}
