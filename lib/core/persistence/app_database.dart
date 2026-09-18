import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('StoredMeterRecord')
class MeterRecords extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get type => text()();
  TextColumn get unit => text()();
  TextColumn get meterNumber => text().withDefault(const Constant(''))();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get vin => text().withDefault(const Constant(''))();
  TextColumn get firstRegistration => text().withDefault(const Constant(''))();
  IntColumn get createdAtMillis => integer()();
  IntColumn get updatedAtMillis => integer()();
  TextColumn get reminderJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StoredReadingRecord')
@TableIndex(
  name: 'reading_meter_captured_idx',
  columns: {#meterId, #capturedAtMillis, #storedAtMillis},
)
@TableIndex(
  name: 'reading_meter_updated_idx',
  columns: {#meterId, #updatedAtMillis},
)
class ReadingRecords extends Table {
  TextColumn get id => text()();
  TextColumn get meterId => text()();
  TextColumn get meterSnapshotJson => text()();
  TextColumn get displayValue => text()();
  TextColumn get valueDigits => text()();
  IntColumn get valueScale => integer()();
  TextColumn get activity => text().withDefault(const Constant('growth'))();
  TextColumn get customActivityLabel => text().nullable()();
  BoolColumn get hasMeasurement =>
      boolean().withDefault(const Constant(true))();
  IntColumn get capturedAtMillis => integer()();
  IntColumn get timezoneOffsetMinutes => integer()();
  IntColumn get storedAtMillis => integer()();
  IntColumn get updatedAtMillis => integer()();
  TextColumn get source => text()();
  TextColumn get photoPath => text()();
  TextColumn get photoSha256 => text()();
  TextColumn get ocrRawText => text().withDefault(const Constant(''))();
  TextColumn get ocrCandidate => text().withDefault(const Constant(''))();
  RealColumn get ocrConfidence => real().nullable()();
  IntColumn get photoAddedAtMillis => integer().nullable()();
  TextColumn get photosJson => text().nullable()();
  TextColumn get photoHistoryJson => text().withDefault(const Constant('[]'))();
  TextColumn get lowerReadingReason => text().nullable()();
  TextColumn get workshop => text().withDefault(const Constant(''))();
  IntColumn get costCents => integer().nullable()();
  TextColumn get documentsJson => text().withDefault(const Constant('[]'))();
  TextColumn get documentHistoryJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get manifestSha256 => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StoredRevisionRecord')
class RevisionRecords extends Table {
  TextColumn get id => text()();
  TextColumn get readingId => text()();
  IntColumn get changedAtMillis => integer()();
  TextColumn get reason => text()();
  TextColumn get documentChangeJson => text().nullable()();
  TextColumn get photoChangeJson => text().nullable()();
  TextColumn get changesJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StoredEvidenceExportRecord')
class EvidenceExportRecords extends Table {
  TextColumn get id => text()();
  TextColumn get meterId => text()();
  TextColumn get kind => text()();
  TextColumn get readingIdsJson => text()();
  IntColumn get createdAtMillis => integer()();
  TextColumn get fileName => text()();
  TextColumn get filePath => text()();
  TextColumn get pdfSha256 => text()();
  TextColumn get manifestSha256 => text()();
  TextColumn get photoMode => text().withDefault(const Constant('allPhotos'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    MeterRecords,
    ReadingRecords,
    RevisionRecords,
    EvidenceExportRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.memory() : super(NativeDatabase.memory());

  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 8) {
        Future<void> addIfMissing(
          TableInfo table,
          GeneratedColumn column,
        ) async {
          final columns = await customSelect(
            'PRAGMA table_info(${table.actualTableName})',
          ).get();
          if (columns.isEmpty) {
            await migrator.createTable(table);
          } else if (!columns.any(
            (row) => row.read<String>('name') == column.name,
          )) {
            await migrator.addColumn(table, column);
          }
        }

        await addIfMissing(meterRecords, meterRecords.vin);
        await addIfMissing(meterRecords, meterRecords.firstRegistration);
        await addIfMissing(readingRecords, readingRecords.workshop);
        await addIfMissing(readingRecords, readingRecords.costCents);
        await addIfMissing(readingRecords, readingRecords.documentsJson);
        await addIfMissing(readingRecords, readingRecords.documentHistoryJson);
        await addIfMissing(revisionRecords, revisionRecords.documentChangeJson);
      }
      if (from < 7) {
        final columns = await customSelect(
          'PRAGMA table_info(reading_records)',
        ).get();
        if (!columns.any(
          (row) => row.read<String>('name') == 'custom_activity_label',
        )) {
          await migrator.addColumn(
            readingRecords,
            readingRecords.customActivityLabel,
          );
        }
      }
      if (from < 5) {
        final columns = await customSelect(
          'PRAGMA table_info(reading_records)',
        ).get();
        if (!columns.any((row) => row.read<String>('name') == 'activity')) {
          await migrator.addColumn(readingRecords, readingRecords.activity);
        }
        if (!columns.any(
          (row) => row.read<String>('name') == 'has_measurement',
        )) {
          await migrator.addColumn(
            readingRecords,
            readingRecords.hasMeasurement,
          );
        }
      }
      if (from < 2) {
        await migrator.addColumn(
          readingRecords,
          readingRecords.photoAddedAtMillis,
        );
        await migrator.addColumn(
          readingRecords,
          readingRecords.photoHistoryJson,
        );
      }
      if (from < 3) {
        await migrator.addColumn(
          evidenceExportRecords,
          evidenceExportRecords.photoMode,
        );
      }
      if (from < 6) {
        // A previous opening may have added columns before its schema version
        // was saved. Complete that migration without replacing existing data.
        final readingColumns = await customSelect(
          'PRAGMA table_info(reading_records)',
        ).get();
        if (!readingColumns.any(
          (row) => row.read<String>('name') == 'photos_json',
        )) {
          await migrator.addColumn(readingRecords, readingRecords.photosJson);
        }
        final revisionColumns = await customSelect(
          'PRAGMA table_info(revision_records)',
        ).get();
        if (!revisionColumns.any(
          (row) => row.read<String>('name') == 'photo_change_json',
        )) {
          await migrator.addColumn(
            revisionRecords,
            revisionRecords.photoChangeJson,
          );
        }
      }
      if (from < 4) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS reading_meter_captured_idx '
          'ON reading_records '
          '(meter_id, captured_at_millis, stored_at_millis)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS reading_meter_updated_idx '
          'ON reading_records (meter_id, updated_at_millis)',
        );
      }
    },
  );
}

QueryExecutor _openConnection() {
  if (_runningInFlutterTest) {
    return NativeDatabase.memory();
  }
  return LazyDatabase(() async {
    Directory directory;
    try {
      directory = await getApplicationDocumentsDirectory();
    } on MissingPluginException {
      directory = await Directory.systemTemp.createTemp(
        'meter_reading_log_db_',
      );
    }
    return NativeDatabase(
      File(p.join(directory.path, 'meter_reading_log.sqlite')),
    );
  });
}

bool get _runningInFlutterTest {
  return Platform.environment.containsKey('FLUTTER_TEST') ||
      Platform.resolvedExecutable.contains('flutter_tester') ||
      Platform.script.toString().contains('flutter_test');
}
