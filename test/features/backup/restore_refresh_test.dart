import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/features/backup/application/backup_file_picker.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/backup/presentation/settings_screen.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/evidence/presentation/evidence_list_providers.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

import '../../support/fakes.dart';
import '../../support/reading_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'refresh reloads cached book, reading, revision, list and file data',
    () async {
      final temp = await Directory.systemTemp.createTemp('restore_refresh_');
      addTearDown(() => temp.delete(recursive: true));
      final pdf = File('${temp.path}/restored.pdf');
      final book = sampleBook();
      final reading = sampleReading();
      final meters = MemoryMeterRepository()..items[book.id] = book;
      final readings = MemoryReadingRepository()..items[reading.id] = reading;
      final exports = MemoryEvidenceExportRepository();
      final container = ProviderContainer(
        overrides: [
          meterRepositoryProvider.overrideWithValue(meters),
          meterReadingRepositoryProvider.overrideWithValue(readings),
          evidenceExportRepositoryProvider.overrideWithValue(exports),
          meterReminderRepositoryProvider.overrideWithValue(
            NoopMeterReminderRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final availability = evidenceFileAvailableProvider(pdf.path);
      final page = evidenceExportPageProvider((
        meterId: book.id,
        kind: EvidenceExportKind.singleReading,
        limit: 10,
        offset: 0,
      ));
      final history = meterHistoryPageProvider((
        meterId: book.id,
        limit: 10,
        offset: 0,
        query: '',
      ));
      container.listen(availability, (_, _) {});
      container.listen(page, (_, _) {});
      container.listen(history, (_, _) {});
      container.listen(meterByIdProvider(book.id), (_, _) {});
      container.listen(readingByIdProvider(reading.id), (_, _) {});
      container.listen(revisionsForReadingProvider(reading.id), (_, _) {});
      container.listen(evidenceForMeterProvider(book.id), (_, _) {});
      expect(
        (await container.read(meterByIdProvider(book.id).future))!.label,
        book.label,
      );
      expect(
        (await container.read(readingByIdProvider(reading.id).future))!.note,
        '',
      );
      expect(
        await container.read(revisionsForReadingProvider(reading.id).future),
        isEmpty,
      );
      expect(
        await container.read(evidenceForMeterProvider(book.id).future),
        isEmpty,
      );
      expect(await container.read(availability.future), isFalse);
      expect((await container.read(page.future)).totalCount, 0);
      expect((await container.read(history.future)).readings.single.note, '');

      await meters.save(book.copyWith(label: 'Importiertes Buch'));
      await readings.save(reading.copyWith(note: 'Importierte Notiz'));
      await readings.saveRevision(
        ReadingRevision(
          id: 'restored',
          readingId: reading.id,
          changedAt: DateTime.utc(2026),
          reason: '',
          changes: const {},
        ),
      );
      await pdf.writeAsBytes([1, 2, 3]);
      await exports.save(
        EvidenceExportRecord(
          id: 'pdf',
          meterId: book.id,
          kind: EvidenceExportKind.singleReading,
          readingIds: [reading.id],
          createdAt: DateTime.utc(2026),
          fileName: 'restored.pdf',
          filePath: pdf.path,
          pdfSha256: 'a' * 64,
          manifestSha256: 'b' * 64,
        ),
      );
      container.read(restoreRevisionProvider.notifier).refresh();
      expect(
        (await container.read(meterByIdProvider(book.id).future))!.label,
        'Importiertes Buch',
      );
      expect(
        (await container.read(readingByIdProvider(reading.id).future))!.note,
        'Importierte Notiz',
      );
      expect(
        await container.read(revisionsForReadingProvider(reading.id).future),
        hasLength(1),
      );
      expect(
        await container.read(evidenceForMeterProvider(book.id).future),
        hasLength(1),
      );
      expect(await container.read(availability.future), isTrue);
      expect((await container.read(page.future)).totalCount, 1);
      expect(
        (await container.read(history.future)).readings.single.note,
        'Importierte Notiz',
      );
      expect(container.read(meterRepositoryProvider), same(meters));
    },
  );

  for (final partialFailure in [false, true]) {
    testWidgets(
      'settings refreshes after restore, partialFailure=$partialFailure',
      (tester) async {
        final service = _RestoreService(partialFailure);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appVersionProvider.overrideWithValue('1.0.0'),
              encryptedBackupServiceProvider.overrideWithValue(service),
              backupFilePickerProvider.overrideWithValue(_Picker()),
            ],
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)),
        );
        expect(container.read(restoreRevisionProvider), 0);
        await tester.tap(find.text('Backup wiederherstellen'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '123456');
        await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
        // The work indicator stays active behind the confirmation dialog.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.widgetWithText(FilledButton, 'Wiederherstellen'));
        await tester.pumpAndSettle();
        expect(service.didWrite, isTrue);
        expect(container.read(restoreRevisionProvider), 1);
        expect(
          find.textContaining(
            partialFailure
                ? 'Backup konnte nicht wiederhergestellt werden'
                : '2 Fotos repariert.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('startup cancels old reminders for books with no schedule', (
    tester,
  ) async {
    final book = sampleBook();
    final reminders = NoopMeterReminderRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meterRepositoryProvider.overrideWithValue(
            MemoryMeterRepository()..items[book.id] = book,
          ),
          meterReadingRepositoryProvider.overrideWithValue(
            MemoryReadingRepository(),
          ),
          evidenceExportRepositoryProvider.overrideWithValue(
            MemoryEvidenceExportRepository(),
          ),
          meterReminderRepositoryProvider.overrideWithValue(reminders),
        ],
        child: const MeterReadingLogApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(reminders.cancelledMeterIds, contains(book.id));
  });
}

class _Picker implements BackupFilePicker {
  @override
  Future<String?> pick() async => '/synthetic.fzbackup';
}

class _RestoreService extends EncryptedBackupService {
  _RestoreService(this.partialFailure)
    : super(
        meters: MemoryMeterRepository(),
        readings: MemoryReadingRepository(),
        exports: MemoryEvidenceExportRepository(),
        reminders: NoopMeterReminderRepository(),
      );
  final bool partialFailure;
  bool didWrite = false;
  @override
  Future<BackupPreview> inspect(String path, String password) async =>
      BackupPreview(
        createdAt: DateTime.utc(2026),
        meterCount: 1,
        readingCount: 1,
        exportCount: 1,
      );
  @override
  Future<BackupImportResult> restore(String path, String password) async {
    await meters.save(sampleBook());
    didWrite = true;
    if (partialFailure) {
      throw StateError('Synthetic failure after first imported record');
    }
    return const BackupImportResult(
      meters: 1,
      readings: 1,
      exports: 1,
      skipped: 0,
      repairedPhotos: 2,
    );
  }
}
