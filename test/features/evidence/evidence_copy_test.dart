import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_copy.dart';
import 'package:fahrzeugakte/features/backup/presentation/settings_screen.dart';

void main() {
  testWidgets('settings no longer exposes PDF verification', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );

    expect(find.text('Nachweise'), findsNothing);
    expect(find.text('PDF auf Änderungen prüfen'), findsNothing);
    expect(find.textContaining('verändert wurde'), findsNothing);
  });

  test('PDF purpose copy stays user-facing and non-technical', () {
    expect(pdfPurposeText, contains('Speichern, Drucken oder Teilen'));
    expect(historyPdfPurposeText, contains('alle Einträge'));
    for (final copy in [pdfPurposeText, historyPdfPurposeText]) {
      expect(copy, isNot(contains('Korrekturen')));
      expect(copy, isNot(contains('Prüfwert')));
      expect(copy, isNot(contains('SHA-256')));
      expect(copy, isNot(contains('verändert')));
    }
  });
}
