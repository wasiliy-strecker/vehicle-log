import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

Meter sampleBook({
  String id = 'book',
  String label = 'Testbuch',
  DateTime? updatedAt,
  ReadingReminderSchedule? reminder,
}) => Meter(
  id: id,
  label: label,
  type: MeterType.electricity,
  unit: 'km',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
  reminder: reminder,
);

MeterReading sampleReading({
  String id = 'reading',
  Meter? book,
  String path = '/synthetic.jpg',
  String? hash,
  String value = '85',
  ReadingSource source = ReadingSource.camera,
}) {
  final meter = book ?? sampleBook();
  final time = DateTime.utc(2026, 9, 14, 12);
  return MeterReading(
    id: id,
    meterId: meter.id,
    meter: MeterSnapshot.fromMeter(meter),
    value: ReadingValue.tryParse(value)!,
    capturedAt: time,
    timezoneOffsetMinutes: 120,
    storedAt: time,
    updatedAt: time,
    source: source,
    photoPath: source == ReadingSource.manual ? '' : path,
    photoSha256: source == ReadingSource.manual ? '' : hash ?? 'a' * 64,
    ocrRawText: source == ReadingSource.manual ? '' : value,
    ocrCandidate: source == ReadingSource.manual ? '' : value,
    ocrConfidence: source == ReadingSource.manual ? null : 0.9,
    photoAddedAt: source == ReadingSource.manual ? null : time,
    note: '',
    manifestSha256: 'historical-hash',
  );
}
