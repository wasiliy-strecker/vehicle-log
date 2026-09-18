import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/app/app_theme.dart';
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/ocr/mlkit_meter_ocr_repository.dart';
import 'package:fahrzeugakte/features/backup/presentation/settings_screen.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/capture_reading_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/edit_reading_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/home_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_detail_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_form_screen.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'actions fit and center on a narrow phone at $scale in $brightness',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final book = sampleBook();
          final reading = sampleReading(source: ReadingSource.manual);
          final router = GoRouter(
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                builder: (_, _) => const HomeScreen(),
              ),
              GoRoute(
                path: '/book/:id',
                name: 'meterDetail',
                builder: (_, _) => MeterDetailScreen(meterId: book.id),
              ),
              GoRoute(
                path: '/capture/:id',
                name: 'captureReading',
                builder: (_, _) => CaptureReadingScreen(meterId: book.id),
              ),
              GoRoute(
                path: '/book/edit/:id',
                name: 'meterEdit',
                builder: (_, _) => MeterFormScreen(meterId: book.id),
              ),
              GoRoute(
                path: '/edit/:id',
                name: 'readingEdit',
                builder: (_, _) => EditReadingScreen(readingId: reading.id),
              ),
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appVersionProvider.overrideWithValue('1.0.0'),
                meterRepositoryProvider.overrideWithValue(
                  MemoryMeterRepository()..items[book.id] = book,
                ),
                meterReadingRepositoryProvider.overrideWithValue(
                  MemoryReadingRepository()..items[reading.id] = reading,
                ),
                evidenceExportRepositoryProvider.overrideWithValue(
                  MemoryEvidenceExportRepository(),
                ),
                meterReminderRepositoryProvider.overrideWithValue(
                  NoopMeterReminderRepository(),
                ),
                evidencePhotoAssetRepositoryProvider.overrideWithValue(
                  const NoopEvidencePhotoAssetRepository(),
                ),
                meterPhotoCaptureRepositoryProvider.overrideWithValue(
                  const UnsupportedMeterPhotoCaptureRepository(),
                ),
                meterOcrRepositoryProvider.overrideWithValue(
                  const UnsupportedMeterOcrRepository(),
                ),
              ],
              child: MaterialApp.router(
                theme: brightness == Brightness.dark
                    ? AppTheme.dark()
                    : AppTheme.light(),
                routerConfig: router,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester
                .renderObject<RenderParagraph>(find.text('Fahrzeug anlegen'))
                .textAlign,
            TextAlign.center,
          );
          router.goNamed('meterDetail', pathParameters: {'id': book.id});
          await tester.pumpAndSettle();
          await _checkAction(tester, 'Fahrzeug & Erinnerung bearbeiten');
          await _checkAction(tester, 'Fahrzeug löschen');
          await _checkAction(
            tester,
            'Fahrzeugprotokoll für den Fahrzeugverlauf erstellen',
          );
          // Reach the editor through the edge of the real book action.
          await _checkAction(
            tester,
            'Fahrzeug & Erinnerung bearbeiten',
            tap: true,
          );
          expect(find.text('Fahrzeug bearbeiten'), findsOneWidget);
          expect(tester.takeException(), isNull);
          router.goNamed('captureReading', pathParameters: {'id': book.id});
          await tester.pumpAndSettle();
          await _checkAction(tester, 'Fahrzeug fotografieren');
          await _checkAction(tester, 'Fotos aus Galerie');
          await _checkAction(tester, 'Ohne Foto erfassen', tap: true);
          expect(find.text('Aktivität'), findsOneWidget);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await _checkAction(tester, 'Datum & Uhrzeit ändern');
          await _checkAction(tester, 'Eintrag speichern');
          router.goNamed('readingEdit', pathParameters: {'id': reading.id});
          await tester.pumpAndSettle();
          await _checkAction(tester, 'Fotos aus Galerie hinzufügen');
          await _checkAction(tester, 'Datum & Uhrzeit ändern');
          await _checkAction(tester, 'Korrektur protokollieren');
          router.go('/settings');
          await tester.pumpAndSettle();
          await _checkAction(tester, 'Datenschutzerklärung öffnen');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _checkAction(
  WidgetTester tester,
  String label, {
  bool tap = false,
}) async {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  final rect = tester.getRect(button);
  final text = tester.getRect(find.text(label));
  expect(
    tester.renderObject<RenderParagraph>(find.text(label)).textAlign,
    TextAlign.center,
    reason: label,
  );
  expect(rect.height, greaterThanOrEqualTo(56 - .001), reason: label);
  final material = find
      .descendant(of: button, matching: find.byType(Material))
      .first;
  expect(
    tester.getSize(material).height,
    greaterThanOrEqualTo(56 - .001),
    reason: label,
  );
  expect(rect.left, greaterThanOrEqualTo(0), reason: label);
  expect(rect.right, lessThanOrEqualTo(320), reason: label);
  expect(rect.contains(text.topLeft), isTrue, reason: label);
  expect(rect.contains(text.bottomRight), isTrue, reason: label);
  expect(tester.takeException(), isNull);
  if (tap) {
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
    await tester.pumpAndSettle();
  }
}
