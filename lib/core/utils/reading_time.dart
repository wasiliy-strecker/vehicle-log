import 'package:intl/intl.dart';

/// SQLite timestamps have millisecond precision. Hash the same representation.
DateTime storageTimestamp(DateTime value) =>
    DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    );

String timestampWithOffset(DateTime instant, int offsetMinutes) {
  final wallTime = instant.toUtc().add(Duration(minutes: offsetMinutes));
  final offset = offsetMinutes.abs();
  final hours = (offset ~/ 60).toString().padLeft(2, '0');
  final minutes = (offset % 60).toString().padLeft(2, '0');
  return '${wallTime.toIso8601String().replaceFirst(RegExp(r'Z$'), '')}'
      '${offsetMinutes < 0 ? '-' : '+'}$hours:$minutes';
}

/// New revisions contain an explicit offset. Old offset-less revisions retain
/// their previous local interpretation; no historical timestamps are rewritten.
String? formatRevisionTimestamp(String value, DateFormat format) {
  final instant = DateTime.tryParse(value);
  if (instant == null) return null;
  final match = RegExp(r'(Z|([+-])(\d{2}):(\d{2}))$').firstMatch(value);
  if (match == null) return format.format(instant.toLocal());
  final offset = match[1] == 'Z'
      ? 0
      : (int.parse(match[3]!) * 60 + int.parse(match[4]!)) *
            (match[2] == '-' ? -1 : 1);
  final label = match[1] == 'Z' ? '+00:00' : match[1]!;
  return '${format.format(instant.toUtc().add(Duration(minutes: offset)))} '
      '(UTC$label)';
}
