import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/persistence/app_database.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/data/drift_meter_repositories.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'create and correct retain valid manifests after SQLite roundtrips',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final meters = DriftMeterRepository(db);
      final readings = DriftMeterReadingRepository(db);
      final book = sampleBook();
      await meters.save(book);
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: DriftEvidenceExportRepository(db),
        photos: const UnsupportedMeterPhotoCaptureRepository(),
        reminders: NoopMeterReminderRepository(),
      );
      final time = DateTime.utc(2026, 9, 14, 12, 0, 0, 123, 456);
      final created = await service.create(
        meter: book,
        photo: StoredMeterPhoto(
          path: '/synthetic.jpg',
          sha256: 'a' * 64,
          source: ReadingSource.camera,
          capturedAt: time,
        ),
        value: ReadingValue.tryParseWhole('85')!,
        capturedAt: time,
        note: '',
      );
      var loaded = (await readings.findById(created.id))!;
      expect(loaded.toJson(), created.toJson());
      expect(
        await const IntegrityService().readingManifestHash(loaded),
        loaded.manifestSha256,
      );
      final corrected = await service.update(
        existing: loaded,
        value: ReadingValue.tryParseWhole('90')!,
        capturedAt: time,
        note: 'Korrektur',
      );
      loaded = (await readings.findById(created.id))!;
      expect(loaded.toJson(), corrected.toJson());
      expect(
        await const IntegrityService().readingManifestHash(loaded),
        loaded.manifestSha256,
      );
      expect(await readings.loadRevisions(created.id), isEmpty);
    },
  );

  test(
    'service rejects invalid new values and allows unchanged legacy decimals',
    () async {
      final meters = MemoryMeterRepository();
      final readings = MemoryReadingRepository();
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: MemoryEvidenceExportRepository(),
        photos: const UnsupportedMeterPhotoCaptureRepository(),
        reminders: NoopMeterReminderRepository(),
      );
      final old = sampleReading(value: '12,5');
      for (final input in ['12-13', '85abc', '1.0', '1,5']) {
        await expectLater(
          service.create(
            meter: sampleBook(),
            photo: StoredMeterPhoto(
              path: '/synthetic.jpg',
              sha256: 'a' * 64,
              source: ReadingSource.camera,
              capturedAt: old.capturedAt,
            ),
            value: ReadingValue.tryParse(input)!,
            capturedAt: old.capturedAt,
            note: '',
          ),
          throwsFormatException,
        );
      }
      expect(readings.items, isEmpty);
      final corrected = await service.update(
        existing: old,
        value: old.value,
        capturedAt: old.capturedAt.toLocal(),
        note: 'Nur Notiz',
      );
      expect(corrected.value.toJson(), old.value.toJson());
      expect(corrected.wasManuallyCorrected, isFalse);
      await expectLater(
        service.update(
          existing: corrected,
          value: ReadingValue.tryParse('13,5')!,
          capturedAt: old.capturedAt,
          note: '',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'note edits preserve original offset and changed times use their new offset',
    () async {
      final readings = MemoryReadingRepository();
      final service = MeterReadingService(
        meters: MemoryMeterRepository(),
        readings: readings,
        exports: MemoryEvidenceExportRepository(),
        photos: const UnsupportedMeterPhotoCaptureRepository(),
        reminders: NoopMeterReminderRepository(),
      );
      final old = sampleReading().copyWith(timezoneOffsetMinutes: -240);
      final corrected = await service.update(
        existing: old,
        value: old.value,
        capturedAt: old.capturedAt.toLocal(),
        note: 'Notiz',
      );
      expect(corrected.timezoneOffsetMinutes, -240);
      expect(corrected.capturedAt, old.capturedAt);
      expect(await readings.loadRevisions(old.id), isEmpty);
      final nextTime = DateTime.utc(2026, 9, 15, 13);
      final changed = await service.update(
        existing: corrected,
        value: old.value,
        capturedAt: nextTime,
        note: corrected.note,
      );
      expect(changed.capturedAt, nextTime);
      expect(changed.timezoneOffsetMinutes, 0);
      expect(await readings.loadRevisions(old.id), isEmpty);
    },
  );

  test(
    'reading deletion removes every single PDF; book deletion removes remaining history PDFs',
    () async {
      final temp = await Directory.systemTemp.createTemp('reading_delete_');
      addTearDown(() => temp.delete(recursive: true));
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final meters = DriftMeterRepository(db);
      final readings = DriftMeterReadingRepository(db);
      final exports = DriftEvidenceExportRepository(db);
      final book = sampleBook();
      await meters.save(book);
      final photo = File('${temp.path}/photo.jpg');
      await photo.writeAsBytes([1, 2, 3]);
      final oldPhoto = File('${temp.path}/old.jpg');
      await oldPhoto.writeAsBytes([4, 5, 6]);
      final reading = sampleReading(path: photo.path).copyWith(
        photoHistory: [
          ReadingPhotoVersion(
            id: 'old-photo',
            path: oldPhoto.path,
            sha256: 'b' * 64,
            source: ReadingSource.gallery,
            addedAt: DateTime.utc(2026),
            ocrRawText: '',
            ocrCandidate: '',
          ),
        ],
      );
      await readings.save(reading);
      await readings.saveRevision(
        ReadingRevision(
          id: 'revision',
          readingId: reading.id,
          changedAt: DateTime.utc(2026),
          reason: '',
          changes: {'Notiz': const ReadingChange(before: '', after: 'Text')},
        ),
      );
      final pdfs = <File>[];
      for (var i = 0; i < 3; i++) {
        final file = File('${temp.path}/$i.pdf');
        await file.writeAsBytes([i]);
        pdfs.add(file);
        await exports.save(
          EvidenceExportRecord(
            id: 'pdf$i',
            meterId: book.id,
            kind: i < 2
                ? EvidenceExportKind.singleReading
                : EvidenceExportKind.meterHistory,
            readingIds: [reading.id],
            createdAt: DateTime.utc(2026),
            fileName: '$i.pdf',
            filePath: file.path,
            pdfSha256: 'c' * 64,
            manifestSha256: 'd' * 64,
          ),
        );
      }
      final photos = _FilePhotos();
      final reminders = NoopMeterReminderRepository();
      await MeterReadingService(
        meters: meters,
        readings: readings,
        exports: exports,
        photos: photos,
        reminders: reminders,
      ).delete(reading);
      expect(await readings.findById(reading.id), isNull);
      expect(await readings.loadRevisions(reading.id), isEmpty);
      expect(await photo.exists(), isFalse);
      expect(await oldPhoto.exists(), isFalse);
      expect(await pdfs[0].exists(), isFalse);
      expect(await pdfs[1].exists(), isFalse);
      expect(await pdfs[2].exists(), isTrue);
      expect(
        (await exports.loadForMeter(book.id)).single.kind,
        EvidenceExportKind.meterHistory,
      );
      await MeterService(
        meters: meters,
        readings: readings,
        exports: exports,
        photos: photos,
        reminders: reminders,
      ).delete(book.id);
      expect(await pdfs[2].exists(), isFalse);
      expect(await exports.loadAll(), isEmpty);
      expect(await meters.findById(book.id), isNull);
    },
  );
}

class _FilePhotos extends UnsupportedMeterPhotoCaptureRepository {
  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
