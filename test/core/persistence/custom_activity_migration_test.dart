import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/reading_fixtures.dart';

void main() {
  for (final partial in [false, true]) {
    test(
      'schema 6 upgrades without changing stored entries or hashes, partial=$partial',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'custom_activity_migration_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final file = File('${temp.path}/old.sqlite');
        final old = AppDatabase.withExecutor(NativeDatabase(file));
        final plant = sampleBook();
        await DriftMeterRepository(old).save(plant);
        var reading = sampleReading().copyWith(
          activity: partial ? CareActivity.custom : CareActivity.watering,
          customActivityLabel: partial ? 'Erste Blüte' : null,
          hasMeasurement: false,
        );
        reading = reading.copyWith(
          manifestSha256: await const IntegrityService().readingManifestHash(
            reading,
          ),
        );
        await DriftMeterReadingRepository(old).save(reading);
        await old.close();
        final upgraded = AppDatabase.withExecutor(
          NativeDatabase(
            file,
            setup: (database) {
              if (!partial) {
                database.execute(
                  'ALTER TABLE reading_records DROP COLUMN custom_activity_label',
                );
              }
              database.execute('PRAGMA user_version = 6');
            },
          ),
        );
        expect(
          (await DriftMeterDashboardRepository(
            upgraded,
          ).watchAll().first).single.latestSummary,
          reading.summary,
        );
        final loaded = (await DriftMeterReadingRepository(
          upgraded,
        ).findById(reading.id))!;
        expect(loaded.toJson(), reading.toJson());
        expect(
          await const IntegrityService().readingManifestHash(loaded),
          reading.manifestSha256,
        );
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          8,
        );
        await upgraded.close();
        final reopened = AppDatabase.withExecutor(NativeDatabase(file));
        addTearDown(reopened.close);
        expect(
          (await DriftMeterReadingRepository(
            reopened,
          ).findById(reading.id))!.toJson(),
          reading.toJson(),
        );
      },
    );
  }
}
