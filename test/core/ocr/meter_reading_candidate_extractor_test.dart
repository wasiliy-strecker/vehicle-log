import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/ocr/meter_ocr_repository.dart';

void main() {
  test('ranks a prominent whole page number before smaller text', () {
    final result = const MeterReadingCandidateExtractor().extract(const [
      OcrCandidateLine(text: 'Buch 1234', confidence: 0.8, height: 14),
      OcrCandidateLine(text: '001234 km', confidence: 0.94, height: 42),
      OcrCandidateLine(text: '2026', confidence: 0.9, height: 10),
    ]);

    expect(result, isNotEmpty);
    expect(result.first.value.canonical, '1234');
  });

  test('deduplicates equivalent OCR candidates', () {
    final result = const MeterReadingCandidateExtractor().extract(const [
      OcrCandidateLine(text: '00123', confidence: 0.8, height: 20),
      OcrCandidateLine(text: '123', confidence: 0.9, height: 24),
    ]);

    expect(result, hasLength(1));
    expect(result.single.confidence, 0.9);
  });
  test(
    'includes single digits and rejects complete non-integer expressions',
    () {
      final result = const MeterReadingCandidateExtractor().extract([
        for (final text in [
          '0',
          '1',
          '9',
          '10',
          '12.5',
          '1,5',
          '.5',
          '12-13',
          '-7',
        ])
          OcrCandidateLine(text: text, confidence: 0.99, height: 20),
      ]);
      expect(
        result.map((item) => item.value.canonical),
        unorderedEquals(['0', '1', '9', '10']),
      );
    },
  );
}
