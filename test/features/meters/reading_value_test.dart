import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

void main() {
  test('parses German decimal values and preserves display text', () {
    final value = ReadingValue.tryParse('00123,45');

    expect(value, isNotNull);
    expect(value!.displayText, '00123,45');
    expect(value.digits, '12345');
    expect(value.scale, 2);
    expect(value.canonical, '123.45');
  });

  test('compares and subtracts values without floating point errors', () {
    final current = ReadingValue.tryParse('1000,10')!;
    final previous = ReadingValue.tryParse('999,9')!;

    expect(current.compareTo(previous), greaterThan(0));
    expect(current.difference(previous).canonical, '0.20');
  });

  test('rejects empty and non-numeric input', () {
    expect(ReadingValue.tryParse(''), isNull);
    expect(ReadingValue.tryParse('kein Wert'), isNull);
  });
  test('new inputs only accept whole numbers and normalize leading zeros', () {
    for (final text in [
      '',
      '-1',
      '+1',
      '1.0',
      '1,5',
      '12-13',
      '85abc',
      '1 000',
      "1'000",
      '1.000',
    ]) {
      expect(ReadingValue.tryParseWhole(text), isNull, reason: text);
    }
    for (final text in [
      '0',
      '1',
      '9',
      '123',
      ' 00123 ',
      '999999999999999999999999',
    ]) {
      final value = ReadingValue.tryParseWhole(text)!;
      expect(value.scale, 0);
      expect(value.unscaled, BigInt.parse(text.trim()));
    }
  });

  test(
    'unchanged legacy decimals survive note edits without reinterpretation',
    () {
      final old = ReadingValue.tryParse('00123,45')!;
      expect(ReadingValue.tryParseEdit('00123,45', old), same(old));
      expect(ReadingValue.tryParseEdit('123,46', old), isNull);
      expect(ReadingValue.tryParseEdit('124', old)!.scale, 0);
    },
  );
}
