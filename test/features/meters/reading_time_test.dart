import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/editable_reading_time_card.dart';

import '../../support/reading_fixtures.dart';

void main() {
  test('reading date range still ends on 31 December 2100', () {
    expect(firstSelectableReadingDate, DateTime(2000));
    expect(lastSelectableReadingDate, DateTime(2100, 12, 31));
  });

  test('future and storage times remain separate in stored data', () {
    final reading = sampleReading(
      source: ReadingSource.manual,
    ).copyWith(capturedAt: DateTime.utc(2100, 1, 1));
    final restored = MeterReading.fromJson(reading.toJson());
    expect(restored.capturedAt, reading.capturedAt);
    expect(restored.storedAt, reading.storedAt);
    expect(restored.wasFutureAtStorage, isTrue);
  });

  testWidgets('future date is displayed normally and remains editable', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditableReadingTimeCard(
            value: DateTime(2100, 1, 1, 12),
            onPressed: () => edits++,
          ),
        ),
      ),
    );
    expect(find.text('Zeitpunkt des Eintrags'), findsOneWidget);
    expect(find.text('01.01.2100, 12:00'), findsOneWidget);
    expect(find.textContaining('Zukunft'), findsNothing);
    expect(find.byIcon(Icons.event_busy_outlined), findsNothing);
    await tester.tap(find.text('Datum & Uhrzeit ändern'));
    expect(edits, 1);
  });
}
