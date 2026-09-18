import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/backup/application/binary_backup_codec.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/data/in_memory_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const integrity = IntegrityService();

  test(
    'free activity accepts custom labels and canonicalizes only presets',
    () {
      for (final preset in CareActivity.presets) {
        final selected = CareActivitySelection.fromText(
          ' ${preset.label.toUpperCase()} ',
        );
        expect(selected.activity, preset);
        expect(selected.customActivityLabel, isNull);
      }
      final selected = CareActivitySelection.fromText('  Blätter besprüht  ');
      expect(selected.activity, CareActivity.custom);
      expect(selected.label, 'Blätter besprüht');
      for (final empty in ['', '  ', '\n']) {
        expect(
          () => CareActivitySelection.fromText(empty),
          throwsArgumentError,
        );
      }
      expect(
        careActivitySuggestions([
          'ERSTE BLÜTE',
          'erste blüte',
          ' wartung ',
          'Tachotausch',
        ]),
        [
          'Wartung',
          'Reparatur',
          'HU/AU',
          'Kilometerstand',
          'ERSTE BLÜTE',
          'Tachotausch',
        ],
      );
    },
  );

  test(
    'custom label participates in integrity and requires a value on import',
    () async {
      final old = sampleReading();
      expect(old.toJson(), isNot(contains('customActivityLabel')));
      expect(MeterReading.fromJson(old.toJson()).toJson(), old.toJson());
      final custom = old.copyWith(
        activity: CareActivity.custom,
        customActivityLabel: 'Erste Blüte',
      );
      expect(custom.summary, startsWith('Erste Blüte'));
      expect(
        await integrity.readingManifestHash(custom),
        isNot(
          await integrity.readingManifestHash(
            custom.copyWith(customActivityLabel: 'Zweite Blüte'),
          ),
        ),
      );
      expect(custom.canCompareGrowthWith(old), isTrue);
      expect(
        custom.copyWith(activity: CareActivity.growth).customActivityLabel,
        isNull,
      );
      for (final label in [null, '', '  ']) {
        final invalid = {...custom.toJson(), 'customActivityLabel': label};
        expect(() => MeterReading.fromJson(invalid), throwsFormatException);
      }
    },
  );

  for (final measured in [false, true]) {
    for (final withPhotos in [false, true]) {
      test(
        'custom activity survives corrections, SQLite and backup, height=$measured photos=$withPhotos',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'custom_activity_',
          );
          addTearDown(() => temp.delete(recursive: true));
          final db = AppDatabase.memory();
          addTearDown(db.close);
          final meters = DriftMeterRepository(db);
          final readings = DriftMeterReadingRepository(db);
          final exports = DriftEvidenceExportRepository(db);
          final reminders = NoopMeterReminderRepository();
          final plant = sampleBook(
            label: 'Testfahrzeug',
            reminder: const ReadingReminderSchedule(
              interval: ReminderInterval.daily,
              day: 1,
              hour: 10,
              minute: 0,
            ),
          ).copyWith(unit: 'mm');
          await meters.save(plant);
          final photoFile = File('${temp.path}/synthetic.jpg')
            ..writeAsBytesSync([1, 2, 3, 4]);
          final photo = ReadingPhotoVersion(
            id: 'p1',
            path: photoFile.path,
            sha256: await integrity.sha256Bytes(await photoFile.readAsBytes()),
            source: ReadingSource.gallery,
            addedAt: DateTime.utc(2026, 9, 18),
            ocrRawText: '',
            ocrCandidate: '',
          );
          final service = MeterReadingService(
            meters: meters,
            readings: readings,
            exports: exports,
            photos: const UnsupportedMeterPhotoCaptureRepository(),
            reminders: reminders,
          );
          final created = await service.createWithPhotos(
            meter: plant,
            photos: withPhotos ? [photo] : [],
            value: ReadingValue.tryParseWhole('42')!,
            activity: CareActivity.custom,
            customActivityLabel: '  Erste Blüte  ',
            hasMeasurement: measured,
            capturedAt: DateTime.utc(2026, 9, 18),
            note: 'Notiz',
          );
          expect(created.activityLabel, 'Erste Blüte');
          final corrected = await service.update(
            existing: created,
            value: created.value,
            capturedAt: created.capturedAt,
            note: created.note,
            reason: 'Bezeichnung präzisiert',
            customActivityLabel: 'Blätter besprüht',
          );
          final loaded = (await readings.findById(created.id))!;
          expect(loaded.toJson(), corrected.toJson());
          expect(
            reminders.scheduledLatestReadings.last!.summary,
            corrected.summary,
          );
          expect(loaded.hasMeasurement, measured);
          expect(loaded.value.displayText, measured ? '42' : '0');
          expect(loaded.hasPhoto, withPhotos);
          expect(loaded.meter.unit, 'mm');
          final revision = (await readings.loadRevisions(created.id)).single;
          expect(revision.changes.keys, ['Aktivität']);
          expect(revision.changes['Aktivität']!.before, 'Erste Blüte');
          expect(revision.changes['Aktivität']!.after, 'Blätter besprüht');
          expect(revision.photoChange, isNull);
          expect(
            (await DriftMeterDashboardRepository(
              db,
            ).watchAll().first).single.latestSummary,
            loaded.summary,
          );
          expect(
            await integrity.readingManifestHash(loaded),
            loaded.manifestSha256,
          );
          final backup = await EncryptedBackupService(
            meters: meters,
            readings: readings,
            exports: exports,
            reminders: reminders,
            kdfIterations: 1000,
            temporaryDirectoryProvider: () async => temp,
            documentsDirectoryProvider: () async => temp,
          ).create('fixture-only');
          final reader = await BinaryBackupReader.open(
            backup.path,
            'fixture-only',
          );
          expect(reader.version, 6);
          reader.close();
          final target = AppDatabase.memory();
          addTearDown(target.close);
          final restoredReadings = DriftMeterReadingRepository(target);
          await EncryptedBackupService(
            meters: DriftMeterRepository(target),
            readings: restoredReadings,
            exports: DriftEvidenceExportRepository(target),
            reminders: reminders,
            kdfIterations: 1000,
            temporaryDirectoryProvider: () async => temp,
            documentsDirectoryProvider: () async =>
                Directory('${temp.path}/restored')..createSync(),
          ).restore(backup.path, 'fixture-only');
          final restored = (await restoredReadings.findById(created.id))!;
          expect(restored.summary, loaded.summary);
          expect(
            await integrity.readingManifestHash(restored),
            loaded.manifestSha256,
          );
          expect(
            (await restoredReadings.loadRevisions(created.id)).single.toJson(),
            revision.toJson(),
          );
          expect(
            await restoredReadings.watchActivitySuggestions().first,
            contains('Blätter besprüht'),
          );
          final standard = await service.update(
            existing: corrected,
            value: corrected.value,
            capturedAt: corrected.capturedAt,
            note: corrected.note,
            reason: '',
            activity: CareActivity.watering,
          );
          expect(standard.activityLabel, 'Wartung');
          expect(standard.customActivityLabel, isNull);
          expect(standard.toJson(), isNot(contains('customActivityLabel')));
          expect(
            await readings.watchActivitySuggestions().first,
            isNot(contains('Blätter besprüht')),
          );
          await expectLater(
            service.update(
              existing: standard,
              value: standard.value,
              capturedAt: standard.capturedAt,
              note: standard.note,
              reason: '',
              activity: CareActivity.custom,
              customActivityLabel: '  ',
            ),
            throwsArgumentError,
          );
          expect(
            (await readings.findById(created.id))!.toJson(),
            standard.toJson(),
          );
        },
      );
    }
  }

  for (final native in [false, true]) {
    test(
      'activity search treats punctuation literally and preserves paging, native=$native',
      () async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final memory = InMemoryMeterReadingRepository();
        addTearDown(memory.dispose);
        final MeterReadingRepository readings = native
            ? DriftMeterReadingRepository(db)
            : memory;
        final labels = [
          'Été: Blätter besprüht',
          'ÉTÉ: BLÄTTER BESPRÜHT',
          'Dosis [1.5%] + Öl',
          'AbcXYZ',
          r'Weg A\B',
        ];
        for (var i = 0; i < labels.length; i++) {
          await readings.save(
            sampleReading(id: '$i').copyWith(
              activity: CareActivity.custom,
              customActivityLabel: labels[i],
              capturedAt: DateTime.utc(2026, 9, 18, i),
            ),
          );
        }
        final first = await readings
            .watchPageForMeter('book', limit: 1, query: 'été: blätter besprüht')
            .first;
        expect(first.matchingCount, 2);
        expect(first.totalCount, 5);
        expect(first.readings.single.id, '1');
        final second = await readings
            .watchPageForMeter(
              'book',
              limit: 1,
              offset: 1,
              query: 'ÉTÉ: BLÄTTER BESPRÜHT',
            )
            .first;
        expect(second.readings.single.id, '0');
        for (final query in ['[1.5%]', '+ Öl', '%', r'A\B']) {
          final page = await readings
              .watchPageForMeter('book', limit: 10, query: query)
              .first;
          expect(page.matchingCount, 1, reason: query);
        }
        for (final query in ['.*', '[', '_', 'Abc.']) {
          final page = await readings
              .watchPageForMeter('book', limit: 10, query: query)
              .first;
          expect(page.matchingCount, query == '[' ? 1 : 0, reason: query);
        }
      },
    );
  }

  for (final native in [false, true]) {
    test(
      'activity phrase search handles differently cased umlauts, native=$native',
      () async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final memory = InMemoryMeterReadingRepository();
        addTearDown(memory.dispose);
        final MeterReadingRepository readings = native
            ? DriftMeterReadingRepository(db)
            : memory;
        final reading = sampleReading().copyWith(
          activity: CareActivity.custom,
          customActivityLabel: 'Äste kürzen',
        );
        await readings.save(reading);
        for (final query in ['äste kürzen', 'ÄSTE KÜRZEN', 'Äste kürzen']) {
          final page = await readings
              .watchPageForMeter(reading.meterId, limit: 10, query: query)
              .first;
          expect(
            page.readings.map((r) => r.id),
            contains(reading.id),
            reason: query,
          );
        }
      },
    );
  }

  for (final native in [false, true]) {
    test(
      'suggestions follow saved edits and deletions across plants, native=$native',
      () async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final memory = InMemoryMeterReadingRepository();
        addTearDown(memory.dispose);
        final MeterReadingRepository readings = native
            ? DriftMeterReadingRepository(db)
            : memory;
        final first = sampleReading(id: 'first').copyWith(
          activity: CareActivity.custom,
          customActivityLabel: 'Blätter besprüht',
          updatedAt: DateTime.utc(2026, 9, 17),
        );
        final second =
            sampleReading(
              id: 'second',
              book: sampleBook(id: 'other'),
            ).copyWith(
              activity: CareActivity.custom,
              customActivityLabel: 'BLÄTTER BESPRÜHT',
              updatedAt: DateTime.utc(2026, 9, 18),
            );
        await readings.save(first);
        await readings.save(second);
        expect(await readings.watchActivitySuggestions().first, [
          'Wartung',
          'Reparatur',
          'HU/AU',
          'Kilometerstand',
          'BLÄTTER BESPRÜHT',
        ]);
        for (final reading in [first, second]) {
          for (final query in ['blätter', 'BLÄTTER', 'besprüht']) {
            final page = await readings
                .watchPageForMeter(reading.meterId, limit: 10, query: query)
                .first;
            expect(page.readings.map((r) => r.id), contains(reading.id));
          }
        }
        await readings.delete(second.id);
        expect(
          (await readings.watchActivitySuggestions().first).last,
          'Blätter besprüht',
        );
        await readings.delete(first.id);
        expect(
          await readings.watchActivitySuggestions().first,
          CareActivity.presets.map((a) => a.label),
        );
        await readings.save(
          sampleReading().copyWith(activity: CareActivity.fertilizing),
        );
        expect(
          (await readings
                  .watchPageForMeter(first.meterId, limit: 10, query: 'repar')
                  .first)
              .matchingCount,
          1,
        );
      },
    );
  }
}
