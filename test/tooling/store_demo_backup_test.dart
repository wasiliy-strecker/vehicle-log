import 'dart:io';

import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/features/backup/application/encrypted_backup_service.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/domain/reading_value.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/fakes.dart';

/// Host-only store fixture. No example photos or demo code ship in the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fixturePath = String.fromEnvironment('STORE_DEMO_DIR');
  test('store demo restores four vehicles, photos, PDFs and integrity', () async {
    final root = fixturePath.isEmpty
        ? await Directory.systemTemp.createTemp('fz-store-demo-')
        : await Directory(fixturePath).create(recursive: true);
    if (fixturePath.isEmpty) addTearDown(() => root.delete(recursive: true));
    final meters = MemoryMeterRepository();
    final readings = MemoryReadingRepository();
    const integrity = IntegrityService();
    final regular = pw.Font.ttf(
      File(
        'assets/fonts/Roboto-Regular.ttf',
      ).readAsBytesSync().buffer.asByteData(),
    );
    final bold = pw.Font.ttf(
      File(
        'assets/fonts/Roboto-Bold.ttf',
      ).readAsBytesSync().buffer.asByteData(),
    );
    final documents = <ReadingDocument>[];
    for (final invoice in [true, false]) {
      final title = invoice ? 'Werkstattrechnung' : 'Prüfbericht';
      final fileName = invoice
          ? 'Werkstattrechnung_MUSTER.pdf'
          : 'Pruefbericht_MUSTER.pdf';
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
      );
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(44),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MUSTER',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 38,
                  color: PdfColors.blueGrey400,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 27)),
              pw.SizedBox(height: 18),
              pw.Text(
                'Musterwerkstatt Nord\nFiktiver Beleg für die Fahrzeugakte-Demonstration',
              ),
              pw.SizedBox(height: 28),
              pw.Text(
                'Fahrzeug: Liefer-Lkw\nDatum: 17.09.2026\nKilometerstand: 184.600 km',
              ),
              pw.SizedBox(height: 26),
              pw.TableHelper.fromTextArray(
                headers: invoice
                    ? ['Leistung', 'Betrag']
                    : ['Prüfpunkt', 'Ergebnis'],
                data: invoice
                    ? [
                        ['Wartung und Ölwechsel', '480,00 €'],
                        ['Filter und Betriebsstoffe', '212,50 €'],
                        ['Bremsen und Beleuchtung prüfen', '200,00 €'],
                        ['Gesamtbetrag', '892,50 €'],
                      ]
                    : [
                        ['Bremsanlage', 'Geprüft'],
                        ['Beleuchtung', 'Geprüft'],
                        ['Reifen und Luftdruck', 'Geprüft'],
                        ['Flüssigkeitsstände', 'Geprüft'],
                      ],
                headerStyle: pw.TextStyle(font: bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey100,
                ),
                cellPadding: const pw.EdgeInsets.all(10),
              ),
              pw.Spacer(),
              pw.Text(
                'Erfundenes Beispiel. Keine echte Rechnung und kein amtlicher Prüfbericht.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      );
      final file = File('${root.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      documents.add(
        ReadingDocument(
          id: invoice ? 'demo-invoice' : 'demo-report',
          fileName: fileName,
          path: file.absolute.path,
          sha256: await integrity.sha256Bytes(await file.readAsBytes()),
          pageCount: 1,
          sizeBytes: await file.length(),
          source: DocumentSource.imported,
          addedAt: DateTime.utc(2026, 9, 17, 8),
        ),
      );
    }
    const vehicles = [
      (
        id: 'auto',
        label: 'Familienauto',
        type: MeterType.electricity,
        model: 'Kompaktwagen',
        count: 12,
        endDay: 18,
        km: 64820,
        step: 1250,
        activity: 'Reifenwechsel',
        cost: 11990,
        registration: '15.03.2020',
        photos: ['01_familienauto.png', '02_reifendetail.png'],
        note: 'Ganzjahresreifen montiert und Reifendruck kontrolliert.',
      ),
      (
        id: 'lkw',
        label: 'Liefer-Lkw',
        type: MeterType.coldWater,
        model: 'Kofferaufbau · 7,5 t',
        count: 8,
        endDay: 17,
        km: 184600,
        step: 4250,
        activity: 'Wartung',
        cost: 89250,
        registration: '02.02.2019',
        photos: ['05_lkw.png'],
        note:
            'Öl und Filter gewechselt. Bremsen und Beleuchtung geprüft. Belege angehängt.',
      ),
      (
        id: 'motorrad',
        label: 'Tourenmotorrad',
        type: MeterType.electricityFeedIn,
        model: 'Tourer',
        count: 6,
        endDay: 16,
        km: 18420,
        step: 850,
        activity: 'Inspektion',
        cost: 16900,
        registration: '20.05.2022',
        photos: ['03_motorrad.png'],
        note:
            'Kette gereinigt, gespannt und geschmiert. Saisoncheck abgeschlossen.',
      ),
      (
        id: 'scooter',
        label: 'Stadt-Scooter',
        type: MeterType.gas,
        model: 'E-Scooter',
        count: 6,
        endDay: 15,
        km: 1280,
        step: 160,
        activity: 'Bremsen geprüft',
        cost: 2900,
        registration: '',
        photos: ['04_scooter.png'],
        note:
            'Bremsen eingestellt, Schrauben kontrolliert und Reifen aufgepumpt.',
      ),
    ];
    const activities = [
      'Wartung',
      'Reparatur',
      'Kilometerstand',
      'Reifen geprüft',
    ];
    for (final vehicle in vehicles) {
      final end = DateTime.utc(2026, 9, vehicle.endDay, 8);
      final meter = Meter(
        id: vehicle.id,
        label: vehicle.label,
        type: vehicle.type,
        unit: 'km',
        location: vehicle.model,
        firstRegistration: vehicle.registration,
        createdAt: DateTime.utc(2025, 1),
        updatedAt: end,
      );
      await meters.save(meter);
      for (var i = 0; i < vehicle.count; i++) {
        final last = i == vehicle.count - 1;
        final at = end.subtract(Duration(days: (vehicle.count - 1 - i) * 28));
        final selection = CareActivitySelection.fromText(
          last ? vehicle.activity : activities[i % activities.length],
        );
        final photos = <ReadingPhotoVersion>[];
        if (last) {
          for (final name in vehicle.photos) {
            final file = File('assets/store_demo/$name').absolute;
            photos.add(
              ReadingPhotoVersion(
                id: '${vehicle.id}-$name',
                path: file.path,
                sha256: await integrity.sha256Bytes(await file.readAsBytes()),
                source: ReadingSource.gallery,
                addedAt: at,
                ocrRawText: '',
                ocrCandidate: '',
              ),
            );
          }
        }
        var reading = MeterReading(
          id: '${vehicle.id}-${i + 1}',
          meterId: meter.id,
          meter: MeterSnapshot.fromMeter(meter),
          value: ReadingValue.tryParse(
            '${vehicle.km - (vehicle.count - 1 - i) * vehicle.step}',
          )!,
          activity: selection.activity,
          customActivityLabel: selection.customActivityLabel,
          hasMeasurement: true,
          capturedAt: at,
          timezoneOffsetMinutes: 120,
          storedAt: at,
          updatedAt: at,
          source: photos.isEmpty ? ReadingSource.manual : ReadingSource.gallery,
          photoPath: photos.firstOrNull?.path ?? '',
          photoSha256: photos.firstOrNull?.sha256 ?? '',
          photos: photos,
          ocrRawText: '',
          ocrCandidate: '',
          manifestSha256: '',
          note: last ? vehicle.note : '',
          workshop: last ? 'Musterwerkstatt Nord' : '',
          costCents: last ? vehicle.cost : null,
          documents: last && vehicle.id == 'lkw' ? documents : [],
        );
        reading = reading.copyWith(
          manifestSha256: await integrity.readingManifestHash(reading),
        );
        await readings.save(reading);
      }
    }
    EncryptedBackupService service(
      MemoryMeterRepository vehicles,
      MemoryReadingRepository entries,
      Directory directory,
    ) => EncryptedBackupService(
      meters: vehicles,
      readings: entries,
      exports: MemoryEvidenceExportRepository(),
      reminders: NoopMeterReminderRepository(),
      temporaryDirectoryProvider: () async => directory,
      documentsDirectoryProvider: () async => directory,
    );
    final backup = await service(meters, readings, root).create('Demo2026');
    final delivery = await File(backup.path).copy('${root.path}/Demo.fzbackup');
    final target = await Directory('${root.path}/roundtrip').create();
    final restoredMeters = MemoryMeterRepository();
    final restoredReadings = MemoryReadingRepository();
    await service(
      restoredMeters,
      restoredReadings,
      target,
    ).restore(delivery.path, 'Demo2026');
    expect(restoredMeters.items.length, 4);
    expect(restoredReadings.items.length, 32);
    expect(
      restoredReadings.items.values.expand((r) => r.currentPhotos).length,
      5,
    );
    expect(restoredReadings.items.values.expand((r) => r.documents).length, 2);
    for (final reading in restoredReadings.items.values) {
      final original = readings.items[reading.id]!;
      expect(reading.activityLabel, original.activityLabel);
      expect(reading.value.canonical, original.value.canonical);
      expect(reading.workshop, original.workshop);
      expect(reading.costCents, original.costCents);
      expect(reading.capturedAt.isBefore(DateTime.utc(2026, 9, 20)), isTrue);
      expect(
        await integrity.readingManifestHash(reading),
        reading.manifestSha256,
      );
      expect(
        reading.currentPhotos.map((p) => p.id),
        original.currentPhotos.map((p) => p.id),
      );
      expect(
        reading.documents.map((p) => p.id),
        original.documents.map((p) => p.id),
      );
      expect(await restoredReadings.loadRevisions(reading.id), isEmpty);
      for (final photo in reading.currentPhotos) {
        expect(
          await integrity.sha256Bytes(await File(photo.path).readAsBytes()),
          photo.sha256,
        );
      }
      for (final doc in reading.documents) {
        expect(
          await integrity.sha256Bytes(await File(doc.path).readAsBytes()),
          doc.sha256,
        );
        expect(doc.pageCount, 1);
        expect(doc.fileName, contains('MUSTER'));
      }
    }
  });
}
