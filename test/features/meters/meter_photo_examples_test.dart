import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app_theme.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_photo_examples.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('plant photo guidance is scrollable and closes, dark=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const Scaffold(body: MeterPhotoExamplesButton()),
        ),
      );
      await tester.tap(find.text('Fotohinweise'));
      await tester.pumpAndSettle();
      expect(find.text('Fahrzeuge fotografieren'), findsOneWidget);
      for (final example in meterPhotoExamples) {
        await tester.scrollUntilVisible(find.text(example.description), 180);
        await tester.pumpAndSettle();
        expect(find.text(example.description), findsOneWidget);
      }
      await tester.scrollUntilVisible(find.byTooltip('Schließen'), -180);
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Fahrzeuge fotografieren'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('busy capture disables photo guidance', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MeterPhotoExamplesButton(enabled: false)),
      ),
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });
}
