import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/core/files/meter_photo_repository.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/core/reminders/local_notification_reminder_repository.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/application/meter_services.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';
import 'multiple_photos_test.dart' show testPhoto;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a failed reminder refresh does not report a committed edit as failed',
    () async {
      final vehicle = sampleBook(
        reminder: const ReadingReminderSchedule(
          interval: ReminderInterval.daily,
          day: 1,
          hour: 9,
          minute: 0,
        ),
      );
      final original = sampleReading(
        book: vehicle,
        source: ReadingSource.manual,
      );
      final meters = MemoryMeterRepository()..items[vehicle.id] = vehicle;
      final readings = _Readings()..items[original.id] = original;
      final service = MeterReadingService(
        meters: meters,
        readings: readings,
        exports: MemoryEvidenceExportRepository(),
        photos: _Photos(),
        reminders: _FailingReminders(),
      );
      final updated = await service.update(
        existing: original,
        value: original.value,
        capturedAt: original.capturedAt,
        note: 'Successfully saved',
      );
      expect(updated.note, 'Successfully saved');
      expect(readings.items[original.id]!.note, updated.note);
      await service.delete(updated);
      expect(readings.items, isEmpty);
    },
  );

  test(
    'ordinary edits keep only current photos and never create revisions',
    () async {
      final original = sampleReading().copyWith(
        photos: [testPhoto('a'), testPhoto('b')],
      );
      final readings = _Readings()..items[original.id] = original;
      final photos = _Photos();
      final result = await _service(readings, photos).update(
        existing: original,
        value: original.value,
        capturedAt: original.capturedAt,
        note: 'Bearbeitet',
        photos: [testPhoto('b'), testPhoto('c')],
      );
      expect(result.currentPhotos.map((p) => p.id), ['b', 'c']);
      expect(result.photoHistory, isEmpty);
      expect(await readings.loadRevisions(original.id), isEmpty);
      expect(photos.deleted, ['/a.jpg']);
      expect(readings.items[original.id]!.note, 'Bearbeitet');
      expect(
        result.manifestSha256,
        await const IntegrityService().readingManifestHash(result),
      );
    },
  );

  test(
    'legacy ID references and hash-only references retain their original files',
    () async {
      for (final hashOnly in [false, true]) {
        final old = testPhoto('old');
        final kept = testPhoto('kept');
        final original = sampleReading().copyWith(
          photos: [kept, testPhoto('removed')],
          photoHistory: [old],
        );
        final revision = ReadingRevision(
          id: 'legacy',
          readingId: original.id,
          changedAt: DateTime.utc(2026),
          reason: 'Alter Datensatz',
          changes: hashOnly
              ? {
                  'Prüfwert des Fotos (SHA-256)': ReadingChange(
                    before: old.sha256,
                    after: kept.sha256,
                  ),
                }
              : {},
          photoChange: hashOnly
              ? null
              : ReadingPhotoChange(beforeIds: ['old'], afterIds: ['kept']),
        );
        final readings = _Readings()
          ..items[original.id] = original
          ..revisions[original.id] = [revision];
        final photos = _Photos();
        final result = await _service(readings, photos).update(
          existing: original,
          value: original.value,
          capturedAt: original.capturedAt,
          note: 'Aktueller Stand',
          photos: [testPhoto('new')],
        );
        expect(result.photoHistory.map((p) => p.id), ['old', 'kept']);
        expect(photos.deleted, ['/removed.jpg']);
        expect(
          (await readings.loadRevisions(original.id)).single.toJson(),
          revision.toJson(),
        );
      }
    },
  );

  test('failed persistence preserves previous files and record', () async {
    final original = sampleReading().copyWith(photos: [testPhoto('a')]);
    final readings = _Readings()
      ..items[original.id] = original
      ..failSave = true;
    final photos = _Photos();
    await expectLater(
      _service(readings, photos).update(
        existing: original,
        value: original.value,
        capturedAt: original.capturedAt,
        note: 'Nicht gespeichert',
        photos: [],
      ),
      throwsStateError,
    );
    expect(readings.items[original.id], same(original));
    expect(photos.deleted, isEmpty);
    expect(readings.revisions, isEmpty);
  });

  test(
    'a cleanup failure does not turn a committed edit into a failed save',
    () async {
      final original = sampleReading().copyWith(photos: [testPhoto('a')]);
      final readings = _Readings()..items[original.id] = original;
      final photos = _Photos()..failDelete = true;
      final result = await _service(readings, photos).update(
        existing: original,
        value: original.value,
        capturedAt: original.capturedAt,
        note: 'Gespeichert',
        photos: [],
      );
      expect(result.currentPhotos, isEmpty);
      expect(readings.items[original.id]!.note, 'Gespeichert');
      expect(readings.revisions, isEmpty);
    },
  );

  test('a file still referenced by another entry is never deleted', () async {
    final original = sampleReading(
      id: 'first',
    ).copyWith(photos: [testPhoto('shared')]);
    final other = sampleReading(
      id: 'second',
    ).copyWith(photos: [testPhoto('shared')]);
    final readings = _Readings()
      ..items[original.id] = original
      ..items[other.id] = other;
    final photos = _Photos();
    await _service(readings, photos).update(
      existing: original,
      value: original.value,
      capturedAt: original.capturedAt,
      note: '',
      photos: [],
    );
    expect(photos.deleted, isEmpty);
    expect(readings.items[other.id], same(other));
  });
  for (final failSave in [false, true]) {
    test(
      'removed PDF files are cleaned only after saving, failure=$failSave',
      () async {
        final root = await Directory.systemTemp.createTemp('edited_pdfs_');
        addTearDown(() => root.delete(recursive: true));
        Future<ReadingDocument> document(String id) async {
          final file = File('${root.path}/$id.pdf');
          await file.writeAsString('%PDF-synthetic-$id');
          return ReadingDocument(
            id: id,
            fileName: '$id.pdf',
            path: file.path,
            sha256: await const IntegrityService().sha256Bytes(
              await file.readAsBytes(),
            ),
            pageCount: 1,
            sizeBytes: await file.length(),
            source: DocumentSource.imported,
            addedAt: DateTime.utc(2026),
          );
        }

        final removed = await document('removed');
        final shared = await document('shared');
        final kept = await document('kept');
        final original = sampleReading().copyWith(
          documents: [removed, shared, kept],
        );
        final other = sampleReading(id: 'other').copyWith(documents: [shared]);
        final readings = _Readings()
          ..items[original.id] = original
          ..items[other.id] = other
          ..failSave = failSave;
        final save = _service(readings, _Photos()).update(
          existing: original,
          value: original.value,
          capturedAt: original.capturedAt,
          note: original.note,
          documents: [kept],
        );
        if (failSave) {
          await expectLater(save, throwsStateError);
          expect(readings.items[original.id], same(original));
        } else {
          final result = await save;
          expect(result.documents.map((d) => d.id), ['kept']);
          expect(result.documentHistory, isEmpty);
        }
        expect(await File(removed.path).exists(), failSave);
        expect(await File(shared.path).exists(), isTrue);
        expect(await File(kept.path).exists(), isTrue);
        expect(readings.revisions, isEmpty);
      },
    );
  }
}

class _FailingReminders extends NoopMeterReminderRepository {
  @override
  Future<ReminderOperationResult> schedule(
    Meter meter, {
    MeterReading? latestReading,
  }) async {
    throw StateError('Synthetic notification failure');
  }
}

MeterReadingService _service(_Readings readings, _Photos photos) =>
    MeterReadingService(
      meters: MemoryMeterRepository(),
      readings: readings,
      exports: MemoryEvidenceExportRepository(),
      photos: photos,
      reminders: NoopMeterReminderRepository(),
    );

class _Readings extends MemoryReadingRepository {
  bool failSave = false;
  @override
  Future<void> save(MeterReading reading) async {
    if (failSave) throw StateError('Simulated write failure');
    await super.save(reading);
  }
}

class _Photos extends UnsupportedMeterPhotoCaptureRepository {
  final deleted = <String>[];
  bool failDelete = false;
  @override
  Future<void> delete(String path) async {
    if (failDelete) throw StateError('Simulated cleanup failure');
    deleted.add(path);
  }
}
