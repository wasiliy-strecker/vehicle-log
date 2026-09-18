import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'vehicle fields and original/current PDFs survive revisions and encrypted restore',
    () async {
      final root = await Directory.systemTemp.createTemp('vehicle_documents_');
      addTearDown(() => root.delete(recursive: true));
      final db = AppDatabase.memory();
      final restoredDb = AppDatabase.memory();
      addTearDown(db.close);
      addTearDown(restoredDb.close);
      final meters = DriftMeterRepository(db);
      final readings = DriftMeterReadingRepository(db);
      final exports = DriftEvidenceExportRepository(db);
      final vehicle = sampleBook(label: 'Familienauto').copyWith(
        meterNumber: 'B-AB 1234',
        location: 'Volkswagen Golf',
        vin: 'SYNTHETIC000000001',
        firstRegistration: '03.2020',
      );
      await meters.save(vehicle);
      expect((await meters.findById(vehicle.id))!.toJson(), vehicle.toJson());
      expect(
        (await DriftMeterDashboardRepository(
          db,
        ).watchAll().first).single.meter.vin,
        vehicle.vin,
      );
      const integrity = IntegrityService();
      Future<ReadingDocument> document(String id) async {
        final file = File('${root.path}/$id.pdf')
          ..writeAsStringSync('%PDF-synthetic-$id');
        return ReadingDocument(
          id: id,
          fileName: '$id.pdf',
          path: file.path,
          sha256: await integrity.sha256Bytes(await file.readAsBytes()),
          pageCount: 2,
          sizeBytes: await file.length(),
          source: DocumentSource.imported,
          addedAt: DateTime.utc(2026),
        );
      }

      final invoice = await document('invoice');
      final report = await document('report');
      final replacement = await document('invoice-corrected');
      final photoFile = File('${root.path}/vehicle.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final photo = ReadingPhotoVersion(
        id: 'photo',
        path: photoFile.path,
        sha256: await integrity.sha256Bytes(await photoFile.readAsBytes()),
        source: ReadingSource.gallery,
        addedAt: DateTime.utc(2026),
        ocrRawText: '',
        ocrCandidate: '',
      );
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: exports,
        photos: const UnsupportedMeterPhotoCaptureRepository(),
        reminders: NoopMeterReminderRepository(),
      );
      final original = await service.createWithPhotos(
        meter: vehicle,
        photos: [photo],
        value: ReadingValue.tryParseWhole('123456')!,
        capturedAt: DateTime.utc(2026, 9, 1),
        activity: CareActivity.watering,
        workshop: 'Musterwerkstatt',
        costCents: 24990,
        documents: [invoice, report],
        note: 'Ölwechsel',
      );
      final changed = await service.update(
        existing: original,
        value: original.value,
        capturedAt: original.capturedAt,
        note: original.note,
        reason: 'Rechnung korrigiert',
        documents: [report, replacement],
        workshop: 'Musterwerkstatt Nord',
        costCents: 21990,
      );
      expect(changed.documentHistory.single.id, invoice.id);
      expect(changed.documents.map((d) => d.id), [
        'report',
        'invoice-corrected',
      ]);
      expect((await readings.findById(changed.id))!.toJson(), changed.toJson());
      final revision = (await readings.loadRevisions(changed.id)).single;
      expect(revision.documentChange!.beforeIds, ['invoice', 'report']);
      expect(revision.documentChange!.afterIds, [
        'report',
        'invoice-corrected',
      ]);
      expect(revision.changes['Kosten']!.after, '219,90 €');
      expect(revision.changes['Werkstatt']!.after, 'Musterwerkstatt Nord');
      expect(
        await integrity.readingManifestHash(changed),
        changed.manifestSha256,
      );
      final backup = EncryptedBackupService(
        meters: meters,
        readings: readings,
        exports: exports,
        reminders: NoopMeterReminderRepository(),
        kdfIterations: 1000,
        documentsDirectoryProvider: () async => root,
        temporaryDirectoryProvider: () async => root,
      );
      final saved = await backup.create('test-password');
      final target = Directory('${root.path}/restore')..createSync();
      final targetReadings = DriftMeterReadingRepository(restoredDb);
      final targetMeters = DriftMeterRepository(restoredDb);
      final restore = EncryptedBackupService(
        meters: targetMeters,
        readings: targetReadings,
        exports: DriftEvidenceExportRepository(restoredDb),
        reminders: NoopMeterReminderRepository(),
        kdfIterations: 1000,
        documentsDirectoryProvider: () async => target,
        temporaryDirectoryProvider: () async => root,
      );
      await restore.restore(saved.path, 'test-password');
      final result = (await targetReadings.findById(changed.id))!;
      expect(result.workshop, changed.workshop);
      expect(result.costCents, 21990);
      expect(result.meter.vin, vehicle.vin);
      expect(
        (await targetMeters.findById(vehicle.id))!.firstRegistration,
        '03.2020',
      );
      expect(
        result.documents.map((d) => d.id),
        changed.documents.map((d) => d.id),
      );
      expect(result.documentHistory.single.id, invoice.id);
      expect(
        (await targetReadings.loadRevisions(changed.id)).single.toJson(),
        revision.toJson(),
      );
      for (final doc in result.allDocuments) {
        expect(doc.path, startsWith(target.path));
        expect(
          await integrity.sha256Bytes(await File(doc.path).readAsBytes()),
          doc.sha256,
        );
      }
      expect(
        await integrity.readingManifestHash(result),
        changed.manifestSha256,
      );
      await File(result.documents.first.path).delete();
      await restore.restore(saved.path, 'test-password');
      expect(await File(result.documents.first.path).exists(), isTrue);
      final cleared = await service.update(
        existing: changed,
        value: changed.value,
        capturedAt: changed.capturedAt,
        note: changed.note,
        reason: '',
        clearCost: true,
        documents: [],
      );
      expect(cleared.costCents, isNull);
      expect(cleared.documents, isEmpty);
      expect(cleared.documentHistory, hasLength(3));
    },
  );

  test(
    'Euro amounts are exact and validation rejects ambiguous or negative input',
    () {
      expect(parseCostCents(' 249,90 € '), 24990);
      expect(parseCostCents('0'), 0);
      expect(parseCostCents('12.5'), 1250);
      expect(parseCostCents(''), isNull);
      for (final value in [
        '-1',
        '12€3',
        '1,234',
        '1.234,56',
        'NaN',
        '12345678901234567890',
      ]) {
        expect(() => parseCostCents(value), throwsFormatException);
      }
    },
  );

  test(
    'kilometers compare across activities but not missing values or units',
    () {
      final a = sampleReading().copyWith(activity: CareActivity.watering);
      final b = sampleReading().copyWith(activity: CareActivity.fertilizing);
      expect(a.canCompareGrowthWith(b), isTrue);
      expect(
        a.canCompareGrowthWith(b.copyWith(hasMeasurement: false)),
        isFalse,
      );
      expect(
        a.canCompareGrowthWith(
          sampleReading(book: sampleBook().copyWith(unit: 'mi')),
        ),
        isFalse,
      );
    },
  );
}
