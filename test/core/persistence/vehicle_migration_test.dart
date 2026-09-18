import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import '../../support/reading_fixtures.dart';

void main() {
  for (final partial in [false, true]) {
    test(
      'schema 7 upgrades vehicle columns and preserves manifests, partial=$partial',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'vehicle_migration_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final file = File('${temp.path}/old.sqlite');
        final old = AppDatabase.withExecutor(NativeDatabase(file));
        final vehicle = sampleBook();
        var reading = sampleReading();
        reading = reading.copyWith(
          manifestSha256: await const IntegrityService().readingManifestHash(
            reading,
          ),
        );
        await DriftMeterRepository(old).save(vehicle);
        await DriftMeterReadingRepository(old).save(reading);
        await old.close();
        final upgraded = AppDatabase.withExecutor(
          NativeDatabase(
            file,
            setup: (db) {
              for (final (table, columns) in [
                ('meter_records', ['vin', 'first_registration']),
                (
                  'reading_records',
                  [
                    'workshop',
                    'cost_cents',
                    'documents_json',
                    'document_history_json',
                  ],
                ),
                ('revision_records', ['document_change_json']),
              ]) {
                for (final column in columns) {
                  if (partial && column == columns.first) continue;
                  db.execute('ALTER TABLE $table DROP COLUMN $column');
                }
              }
              db.execute('PRAGMA user_version = 7');
            },
          ),
        );
        addTearDown(upgraded.close);
        final loaded = (await DriftMeterReadingRepository(
          upgraded,
        ).findById(reading.id))!;
        expect(loaded.toJson(), reading.toJson());
        expect(
          await const IntegrityService().readingManifestHash(loaded),
          reading.manifestSha256,
        );
        expect(
          (await DriftMeterRepository(upgraded).findById(vehicle.id))!.toJson(),
          vehicle.toJson(),
        );
        expect(loaded.documents, isEmpty);
        expect(loaded.costCents, isNull);
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          8,
        );
      },
    );
  }
}
