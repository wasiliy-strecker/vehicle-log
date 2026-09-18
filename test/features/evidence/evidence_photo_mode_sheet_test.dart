import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app_theme.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/evidence/presentation/evidence_photo_mode_sheet.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final kind in EvidenceExportKind.values) {
      for (final hasPhotos in [false, true]) {
        testWidgets('$brightness $kind photos=$hasPhotos at large text', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(const Size(360, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final theme = brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light();
          EvidencePhotoMode? selection;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () async {
                      selection = await showEvidencePhotoModeSheet(
                        context,
                        kind: kind,
                        hasCurrentPhotos: hasPhotos,
                      );
                    },
                    child: const Text('PDF öffnen'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('PDF öffnen'));
          await tester.pumpAndSettle();
          final photo = find.byKey(
            const ValueKey('evidence-photo-mode-currentPhotos'),
          );
          await tester.ensureVisible(photo);
          await tester.pumpAndSettle();
          final tile = tester.widget<ListTile>(photo);
          expect(tile.enabled, hasPhotos);
          expect(tile.onTap, hasPhotos ? isNotNull : isNull);
          expect(tile.trailing, hasPhotos ? isNotNull : isNull);
          expect(
            find.text(
              kind == EvidenceExportKind.singleReading
                  ? EvidencePhotoMode.currentPhotos.labelFor(kind)
                  : 'Mit Fotos und PDFs',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(photo);
          await tester.pumpAndSettle();
          if (hasPhotos) {
            expect(selection, EvidencePhotoMode.currentPhotos);
            expect(find.text('PDF-Inhalt wählen'), findsNothing);
          } else {
            expect(selection, isNull);
            expect(find.text('PDF-Inhalt wählen'), findsOneWidget);
            final hint = find.text(
              'Keine aktuellen Fotos oder PDFs vorhanden.',
            );
            expect(hint, findsOneWidget);
            final foreground = tester.widget<Text>(hint).style!.color!;
            final background =
                theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow;
            final a = foreground.computeLuminance();
            final b = background.computeLuminance();
            final contrast = a > b
                ? (a + .05) / (b + .05)
                : (b + .05) / (a + .05);
            expect(contrast, greaterThanOrEqualTo(4.5));
            final compact = find.byKey(
              const ValueKey('evidence-photo-mode-withoutPhotos'),
            );
            await tester.ensureVisible(compact);
            await tester.pumpAndSettle();
            expect(tester.widget<ListTile>(compact).enabled, isTrue);
            await tester.tap(compact);
            await tester.pumpAndSettle();
            expect(selection, EvidencePhotoMode.withoutPhotos);
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
}
