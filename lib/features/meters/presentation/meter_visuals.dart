import 'package:flutter/material.dart';

import '../domain/meter.dart';

IconData meterIcon(MeterType type) => switch (type) {
  MeterType.electricity => Icons.directions_car_outlined,
  MeterType.electricityFeedIn => Icons.two_wheeler_outlined,
  MeterType.gas => Icons.moped_outlined,
  MeterType.water => Icons.airport_shuttle_outlined,
  MeterType.coldWater => Icons.local_shipping_outlined,
  MeterType.hotWater => Icons.rv_hookup_outlined,
  MeterType.heat => Icons.holiday_village_outlined,
  MeterType.heatingCostAllocator => Icons.local_shipping_outlined,
  MeterType.oil => Icons.pedal_bike_outlined,
  MeterType.other => Icons.commute_outlined,
};

Color meterColor(MeterType type, Brightness brightness) {
  final base = switch (type) {
    MeterType.electricity => const Color(0xFF315E80),
    MeterType.electricityFeedIn => const Color(0xFF476783),
    MeterType.gas => const Color(0xFF50657A),
    MeterType.water => const Color(0xFF326877),
    MeterType.coldWater => const Color(0xFF465D72),
    MeterType.hotWater => const Color(0xFF53697F),
    MeterType.heat => const Color(0xFF526876),
    MeterType.heatingCostAllocator => const Color(0xFF455B70),
    MeterType.oil => const Color(0xFF2F6676),
    MeterType.other => const Color(0xFF556777),
  };
  // Preserve category hues while keeping text and icons readable on dark cards.
  return brightness == Brightness.dark
      ? Color.lerp(base, Colors.white, .55)!
      : base;
}
