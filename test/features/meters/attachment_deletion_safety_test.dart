import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/evidence/application/evidence_report_service.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase database;
  late DriftMeterRepository meters;
  late DriftMeterReadingRepository readings;
  late DriftEvidenceExportRepository exports;
  late MeterReading reading;
  late EvidenceExportRecord single;
  late EvidenceExportRecord history;
  late MeterReadingService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('attachment_delete_');
    database = AppDatabase.memory();
    meters = DriftMeterRepository(database);
    readings = DriftMeterReadingRepository(database);
    exports = DriftEvidenceExportRepository(database);
    final vehicle = sampleBook();
    await meters.save(vehicle);
    final file = File('${root.path}/original.pdf')
      ..writeAsStringSync('%PDF-synthetic-attachment');
    reading = sampleReading(book: vehicle, source: ReadingSource.manual)
        .copyWith(
          documents: [
            ReadingDocument(
              id: 'document',
              fileName: 'original.pdf',
              path: file.path,
              sha256: 'a' * 64,
              pageCount: 1,
              sizeBytes: file.lengthSync(),
              source: DocumentSource.imported,
              addedAt: DateTime.utc(2026),
            ),
          ],
        );
    await readings.save(reading);
    EvidenceExportRecord report(String id, EvidenceExportKind kind) {
      final reportFile = File('${root.path}/$id.pdf')
        ..writeAsStringSync('%PDF-synthetic-$id');
      return EvidenceExportRecord(
        id: id,
        meterId: vehicle.id,
        kind: kind,
        readingIds: [reading.id],
        createdAt: DateTime.utc(2026),
        fileName: '$id.pdf',
        filePath: reportFile.path,
        pdfSha256: 'b' * 64,
        manifestSha256: 'c' * 64,
      );
    }

    single = report('single', EvidenceExportKind.singleReading);
    history = report('history', EvidenceExportKind.meterHistory);
    await exports.save(single);
    await exports.save(history);
    service = MeterReadingService(
      meters: meters,
      readings: readings,
      exports: exports,
      photos: const UnsupportedMeterPhotoCaptureRepository(),
      reminders: NoopMeterReminderRepository(),
      transaction: (operation) => database.transaction(operation),
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  Future<void> failDeletion(String table) => database.customStatement('''
    CREATE TRIGGER fail_delete BEFORE DELETE ON $table
    BEGIN SELECT RAISE(ABORT, 'synthetic delete failure'); END
  ''');

  Future<void> expectPreserved() async {
    expect(await meters.findById(reading.meterId), isNotNull);
    expect(await readings.findById(reading.id), isNotNull);
    expect(await exports.loadAll(), hasLength(2));
    for (final path in [
      reading.documents.single.path,
      single.filePath,
      history.filePath,
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  }

  test(
    'failed entry deletion rolls back exports and preserves every PDF',
    () async {
      await failDeletion('reading_records');
      await expectLater(service.delete(reading), throwsA(isA<Exception>()));
      await expectPreserved();
    },
  );

  test(
    'failed vehicle deletion rolls back entries, reports and files',
    () async {
      await failDeletion('meter_records');
      final container = ProviderContainer(
        overrides: [
          meterRepositoryProvider.overrideWithValue(meters),
          meterReadingRepositoryProvider.overrideWithValue(readings),
          evidenceExportRepositoryProvider.overrideWithValue(exports),
          meterPhotoCaptureRepositoryProvider.overrideWithValue(
            const UnsupportedMeterPhotoCaptureRepository(),
          ),
          meterReminderRepositoryProvider.overrideWithValue(
            NoopMeterReminderRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final vehicles = container.read(meterServiceProvider);
      await expectLater(
        vehicles.delete(reading.meterId),
        throwsA(isA<Exception>()),
      );
      await expectPreserved();
    },
  );

  test('failed report deletion preserves its file and stored record', () async {
    await failDeletion('evidence_export_records');
    await expectLater(
      EvidenceReportService(exports: exports).delete(history),
      throwsA(isA<Exception>()),
    );
    await expectPreserved();
  });

  test(
    'deleting an entry removes its PDFs but keeps the saved history',
    () async {
      await service.delete(reading);
      expect(await readings.findById(reading.id), isNull);
      expect(File(reading.documents.single.path).existsSync(), isFalse);
      expect(File(single.filePath).existsSync(), isFalse);
      expect(File(history.filePath).existsSync(), isTrue);
      expect((await exports.loadAll()).single.id, history.id);
    },
  );

  test('a PDF shared by another entry survives deletion', () async {
    await readings.save(
      MeterReading.fromJson({...reading.toJson(), 'id': 'other'}),
    );
    await service.delete(reading);
    expect(File(reading.documents.single.path).existsSync(), isTrue);
    expect(await readings.findById('other'), isNotNull);
  });

  test('failed report save removes the unregistered generated PDF', () async {
    await database.customStatement('''
      CREATE TRIGGER fail_export BEFORE INSERT ON evidence_export_records
      BEGIN SELECT RAISE(ABORT, 'synthetic save failure'); END
    ''');
    final service = EvidenceReportService(
      exports: exports,
      documentsDirectoryProvider: () async => root,
    );
    await expectLater(
      service.createSingle(
        reading: reading,
        revisions: [],
        photoMode: EvidencePhotoMode.withoutPhotos,
      ),
      throwsA(isA<Exception>()),
    );
    expect(Directory('${root.path}/evidence_reports').listSync(), isEmpty);
    await expectPreserved();
  });
}
