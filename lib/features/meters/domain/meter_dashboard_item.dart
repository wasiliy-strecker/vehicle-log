import 'meter.dart';
import 'meter_reading.dart';
import 'reading_value.dart';

class MeterDashboardItem {
  const MeterDashboardItem({
    required this.meter,
    required this.lastEdited,
    this.latestValue,
    this.latestUnit,
    this.latestActivity,
    this.latestCustomActivityLabel,
    this.latestHasMeasurement = true,
  });

  final Meter meter;
  final ReadingValue? latestValue;
  final String? latestUnit;
  final DateTime lastEdited;
  final CareActivity? latestActivity;
  final String? latestCustomActivityLabel;
  final bool latestHasMeasurement;

  String get latestSummary {
    if (latestActivity == null && latestValue == null) {
      return 'Noch kein Eintrag';
    }
    final label = latestActivity == CareActivity.custom
        ? latestCustomActivityLabel!
        : latestActivity?.label ?? CareActivity.growth.label;
    return latestHasMeasurement && latestValue != null
        ? '$label · ${latestValue!.displayText} ${latestUnit ?? meter.unit}'
        : label;
  }
}
