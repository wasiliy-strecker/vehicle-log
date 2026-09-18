import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';

void main() {
  test('every meter type exposes a valid default and unique unit options', () {
    for (final type in MeterType.values) {
      expect(type.label, isNotEmpty);
      expect(type.availableUnits, isNotEmpty);
      expect(type.availableUnits, contains(type.defaultUnit));
      expect(
        type.availableUnits.toSet(),
        hasLength(type.availableUnits.length),
      );
    }
  });

  test('meter types expose the ten book categories', () {
    expect(MeterType.values.map((type) => type.label), [
      'Pkw',
      'Motorrad',
      'Roller',
      'Transporter',
      'Lkw',
      'Wohnmobil',
      'Wohnwagen',
      'Anhänger',
      'Fahrrad',
      'Sonstiges',
    ]);
    for (final type in MeterType.values) {
      expect(type.availableUnits, const ['km', 'mi']);
      expect(type.defaultUnit, 'km');
    }
  });

  test('unit catalog defaults to pages and keeps custom units', () {
    expect(meterUnitCatalogValues, const ['km', 'mi']);
    expect(meterUnitDescription('km'), 'km – Kilometerstand');
    expect(meterUnitDescription('Kapitel'), 'Eigene Einheit dieses Fahrzeugs');
  });
}
