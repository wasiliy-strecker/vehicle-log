import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/data/in_memory_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const integrity = IntegrityService();

  test(
    'care fields survive SQLite, dashboard, JSON, revisions and backup',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final meters = DriftMeterRepository(db);
      final readings = DriftMeterReadingRepository(db);
      final exports = DriftEvidenceExportRepository(db);
      final reminders = NoopMeterReminderRepository();
      final plant = sampleBook(
        label: 'Familienauto',
      ).copyWith(meterNumber: 'B-AB 1234', location: 'Volkswagen Golf');
      await meters.save(plant);
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: exports,
        photos: const UnsupportedMeterPhotoCaptureRepository(),
        reminders: reminders,
      );
      final created = <MeterReading>[];
      for (final activity in CareActivity.presets) {
        final reading = await service.createManual(
          meter: plant,
          activity: activity,
          hasMeasurement: activity == CareActivity.growth,
          value: ReadingValue.tryParseWhole('42')!,
          capturedAt: DateTime.utc(2026, 9, 16, activity.index),
          note: 'Notiz ${activity.label}',
        );
        created.add(reading);
        final stored = (await readings.findById(reading.id))!;
        expect(stored.toJson(), reading.toJson());
        expect(
          MeterReading.fromJson(stored.toJson()).toJson(),
          stored.toJson(),
        );
        expect(
          await integrity.readingManifestHash(stored),
          stored.manifestSha256,
        );
        if (activity != CareActivity.growth) {
          expect(stored.summary, activity.label);
          expect(stored.summary, isNot(contains('0 km')));
        }
        final card = (await DriftMeterDashboardRepository(
          db,
        ).watchAll().first).single;
        expect(card.latestSummary, stored.summary);
      }
      final old = created.first;
      final corrected = await service.update(
        existing: old,
        activity: CareActivity.fertilizing,
        hasMeasurement: false,
        value: old.value,
        capturedAt: old.capturedAt,
        note: old.note,
        reason: '',
      );
      expect(corrected.activity, CareActivity.fertilizing);
      expect(corrected.manifestSha256, isNot(old.manifestSha256));
      expect(
        (await readings.loadRevisions(
          old.id,
        )).single.changes['Aktivität']!.after,
        'Reparatur',
      );
      final growth = created.last;
      final cleared = await service.update(
        existing: growth,
        hasMeasurement: false,
        value: growth.value,
        capturedAt: growth.capturedAt,
        note: growth.note,
        reason: '',
      );
      expect(cleared.summary, 'Kilometerstand');
      final revision = (await readings.loadRevisions(growth.id)).single;
      expect(
        revision.changes['Kilometerangabe']!.after,
        'Ohne Kilometerangabe',
      );
      expect(revision.changes, isNot(contains('Kilometerstand')));

      final temp = await Directory.systemTemp.createTemp('plant_care_backup_');
      addTearDown(() => temp.delete(recursive: true));
      final backup = await EncryptedBackupService(
        meters: meters,
        readings: readings,
        exports: exports,
        reminders: reminders,
        kdfIterations: 1000,
        temporaryDirectoryProvider: () async => temp,
        documentsDirectoryProvider: () async => temp,
      ).create('123456');
      expect(backup.path, endsWith('.fzbackup'));
      final targetDb = AppDatabase.memory();
      addTearDown(targetDb.close);
      final targetReadings = DriftMeterReadingRepository(targetDb);
      final target = EncryptedBackupService(
        meters: DriftMeterRepository(targetDb),
        readings: targetReadings,
        exports: DriftEvidenceExportRepository(targetDb),
        reminders: NoopMeterReminderRepository(),
        kdfIterations: 1000,
        temporaryDirectoryProvider: () async => temp,
        documentsDirectoryProvider: () async => temp,
      );
      await target.restore(backup.path, '123456');
      for (final reading in await readings.loadAll()) {
        final restored = (await targetReadings.findById(reading.id))!;
        expect(restored.toJson(), reading.toJson());
        expect(
          await integrity.readingManifestHash(restored),
          restored.manifestSha256,
        );
      }
      expect(
        (await targetReadings.loadRevisions(
          old.id,
        )).single.changes['Aktivität']!.after,
        'Reparatur',
      );
    },
  );

  test(
    'web dashboard preserves the last care action without a height',
    () async {
      final meters = InMemoryMeterRepository();
      final readings = InMemoryMeterReadingRepository();
      addTearDown(meters.dispose);
      addTearDown(readings.dispose);
      final plant = sampleBook();
      await meters.save(plant);
      await readings.save(
        sampleReading(
          book: plant,
        ).copyWith(activity: CareActivity.watering, hasMeasurement: false),
      );
      final dashboard = CombinedMeterDashboardRepository(
        meters: meters,
        readings: readings,
      );
      final summaries = <String>[];
      final subscription = dashboard.watchAll().listen((items) {
        summaries.add(items.single.latestSummary);
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(summaries, ['Wartung']);
      await readings.dispose();
      await meters.dispose();
      await subscription.cancel();
    },
  );

  test('kilometer comparison skips missing measurements', () {
    final before = sampleReading(value: '30');
    final after = sampleReading(value: '42');
    expect(after.canCompareGrowthWith(before), isTrue);
    for (final other in [before.copyWith(hasMeasurement: false)]) {
      expect(after.canCompareGrowthWith(other), isFalse);
      final rows = EvidenceReportService.historyTableData([
        after,
        other,
      ], DateFormat('dd.MM.yyyy'));
      expect(rows.first[2], '–');
    }
    final care = before.copyWith(
      activity: CareActivity.repotting,
      hasMeasurement: false,
    );
    final rows = EvidenceReportService.historyTableData([
      care,
    ], DateFormat('dd.MM.yyyy'));
    expect(rows.single[1], 'HU/AU');
    expect(rows.single.join(' '), isNot(contains('30 km')));
  });

  test(
    'schema 4 migration preserves rows and adds care field defaults',
    () async {
      final db = AppDatabase.withExecutor(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute('CREATE TABLE reading_records (id TEXT NOT NULL)');
            sqlite.execute("INSERT INTO reading_records VALUES ('old-entry')");
            sqlite.execute(
              'CREATE TABLE revision_records (id TEXT PRIMARY KEY)',
            );
            sqlite.execute('PRAGMA user_version = 4');
          },
        ),
      );
      addTearDown(db.close);
      final row = await db
          .customSelect('SELECT * FROM reading_records')
          .getSingle();
      expect(row.read<String>('id'), 'old-entry');
      expect(row.read<String>('activity'), 'growth');
      expect(row.read<bool>('has_measurement'), isTrue);
    },
  );
}
