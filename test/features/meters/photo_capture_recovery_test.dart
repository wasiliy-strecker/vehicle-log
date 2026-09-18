import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/files/photo_draft_store.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/capture_reading_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/edit_reading_screen.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  for (final editing in [false, true]) {
    for (final measured in [false, true]) {
      for (final activityText in [null, '', '  Erste Blü  ']) {
        testWidgets(
          'failed recovery preserves form fields and clears pending picker, editing=$editing, measured=$measured, activity=$activityText',
          (tester) async {
            final recovered = Completer<StoredMeterPhoto?>();
            final photos = _Photos(pendingRecovery: recovered.future);
            final drafts = MemoryPhotoDraftStore();
            await _open(
              tester,
              editing: editing,
              photos: photos,
              settle: false,
              drafts: drafts,
              draftFields: {
                'value': measured ? '237' : '',
                'hasMeasurement': measured,
                'activity': 'fertilizing',
                'activityText': ?activityText,
                'selectedUnit': 'mm',
                'note': 'Ärmel fortsetzen',
                'reason': 'Foto ergänzen',
                'manual': true,
              },
            );
            recovered.completeError(StateError('Picker interrupted'));
            await tester.pumpAndSettle();
            expect(
              find.textContaining(
                'Foto-Zwischenstand konnte nicht wiederhergestellt werden',
              ),
              findsOneWidget,
            );
            final value = find.widgetWithText(
              TextFormField,
              'Kilometerstand (optional)',
            );
            await tester.ensureVisible(value);
            expect(
              tester.widget<TextFormField>(value).controller!.text,
              measured ? '237' : '',
            );
            final note = find.widgetWithText(TextFormField, 'Notiz');
            await tester.ensureVisible(note);
            expect(
              tester.widget<TextFormField>(note).controller!.text,
              'Ärmel fortsetzen',
            );
            if (editing) {
              final reason = find.widgetWithText(
                TextFormField,
                'Grund der Korrektur (optional)',
              );
              await tester.ensureVisible(reason);
              expect(
                tester.widget<TextFormField>(reason).controller!.text,
                'Foto ergänzen',
              );
            }
            expect(
              tester
                  .widget<TextFormField>(
                    find.byKey(const ValueKey('care-activity')),
                  )
                  .controller!
                  .text,
              activityText ?? 'Reparatur',
            );
            expect(await drafts.pendingRoute(), null);
            expect(photos.deleted, isEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
    testWidgets(
      'photo remains attached to manually entered value, editing=$editing',
      (tester) async {
        final photos = _Photos();
        final readings = await _open(tester, editing: editing, photos: photos);
        await _capture(tester, editing: editing);
        await tester.pumpAndSettle();
        expect(find.textContaining('Texterkennung'), findsNothing);
        expect(photos.deleted, isEmpty);
        // Let the temporary error message clear the bottom action area.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        final value = find.widgetWithText(
          TextFormField,
          'Kilometerstand (optional)',
        );
        await tester.ensureVisible(value);
        if (!editing) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('care-activity')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('care-activity')),
            'Kilometerstand',
          );
        }
        await tester.enterText(value, '7');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final save = find.widgetWithText(
          FilledButton,
          editing
              ? 'Korrektur protokollieren'
              : 'Eintrag bestätigen und speichern',
        );
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        for (
          var attempt = 0;
          attempt < 50 &&
              !readings.items.values.any((r) => r.value.displayText == '7');
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final saved = readings.items.values.single;
        expect(saved.value.displayText, '7');
        expect(saved.photoPath, '/new-1.jpg');
        expect(saved.ocrCandidate, isEmpty);
        expect(saved.ocrConfidence, isNull);
        if (editing) {
          expect(saved.photoHistory.single.path, '/synthetic.jpg');
          expect(
            (await readings.loadRevisions(saved.id)).single.reason,
            isEmpty,
          );
        }
        await tester.pumpWidget(const SizedBox());
        expect(photos.deleted, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    for (final lateStage in ['capture', 'recovery']) {
      testWidgets('leaving cleans late $lateStage photo, editing=$editing', (
        tester,
      ) async {
        final captured = Completer<StoredMeterPhoto?>();
        final photos = _Photos(
          pendingCapture: lateStage == 'capture' ? captured.future : null,
          pendingRecovery: lateStage == 'recovery' ? captured.future : null,
        );
        await _open(
          tester,
          editing: editing,
          photos: photos,
          settle: lateStage != 'recovery',
        );
        if (lateStage != 'recovery') await _capture(tester, editing: editing);
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        captured.complete(_photo(1));
        await tester.pump();
        expect(photos.deleted, ['/new-1.jpg']);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'replacing and abandoning unsaved photos cleans each one, editing=$editing',
      (tester) async {
        final photos = _Photos();
        await _open(tester, editing: editing, photos: photos);
        await _capture(tester, editing: editing);
        await tester.pumpAndSettle();
        final valueField = find.widgetWithText(
          TextFormField,
          'Kilometerstand (optional)',
        );
        await tester.ensureVisible(valueField);
        await tester.enterText(valueField, '237');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final replace = find.byTooltip('Foto 1 bearbeiten');
        await tester.ensureVisible(replace);
        await tester.tap(replace);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Foto ersetzen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Neu fotografieren'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(valueField).controller!.text,
          '237',
        );
        expect(photos.deleted, ['/new-1.jpg']);
        await tester.pumpWidget(const SizedBox());
        expect(photos.deleted, ['/new-1.jpg', '/new-2.jpg']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<MemoryReadingRepository> _open(
  WidgetTester tester, {
  required bool editing,
  required _Photos photos,
  bool settle = true,
  MemoryPhotoDraftStore? drafts,
  Map<String, dynamic> draftFields = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final book = sampleBook();
  final readings = MemoryReadingRepository();
  if (editing) readings.items['reading'] = sampleReading();
  drafts ??= MemoryPhotoDraftStore();
  if (photos.pendingRecovery != null) {
    final original = editing ? sampleReading() : null;
    await drafts.write(
      editing ? '/reading/reading/edit' : '/meter/${book.id}/capture',
      {
        'originalUpdatedAt': original?.updatedAt.toIso8601String(),
        'photos': original?.currentPhotos.map((p) => p.toJson()).toList() ?? [],
        'ownedPaths': <String>[],
        'fields': {
          'value': '',
          'note': '',
          'reason': '',
          'manual': false,
          'photoEntry': false,
          'capturedAt': DateTime.now().toIso8601String(),
          'initialCapturedAt': DateTime.now().toIso8601String(),
          ...draftFields,
        },
        'pendingSource': 'camera',
        if (original != null) 'replacementId': original.currentPhotos.single.id,
      },
    );
  }
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => editing
            ? const EditReadingScreen(readingId: 'reading')
            : CaptureReadingScreen(meterId: book.id),
      ),
      GoRoute(
        path: '/reading/:id',
        name: 'readingDetail',
        builder: (_, _) => const Scaffold(body: Text('Gespeichert')),
      ),
      GoRoute(
        path: '/book/:id',
        name: 'meterDetail',
        builder: (_, _) => const Scaffold(),
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
        photoDraftStoreProvider.overrideWithValue(drafts),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return readings;
}

Future<void> _capture(WidgetTester tester, {required bool editing}) async {
  if (editing) {
    final menu = find.byTooltip('Foto 1 bearbeiten');
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Foto ersetzen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neu fotografieren'));
  } else {
    await tester.tap(find.text('Fahrzeug fotografieren'));
  }
  await tester.pump();
}

StoredMeterPhoto _photo(int index) => StoredMeterPhoto(
  path: '/new-$index.jpg',
  sha256: 'b' * 64,
  source: ReadingSource.camera,
  capturedAt: DateTime.utc(2026, 1, 1),
);

class _Photos extends UnsupportedMeterPhotoCaptureRepository {
  _Photos({this.pendingCapture, this.pendingRecovery});
  final Future<StoredMeterPhoto?>? pendingCapture;
  final Future<StoredMeterPhoto?>? pendingRecovery;
  final deleted = <String>[];
  var captures = 0;
  @override
  Future<StoredMeterPhoto?> capture(ReadingSource source) async =>
      pendingCapture ?? _photo(++captures);
  @override
  Future<StoredMeterPhoto?> recoverLostCapture() async => pendingRecovery;
  @override
  Future<void> delete(String path) async => deleted.add(path);
}
