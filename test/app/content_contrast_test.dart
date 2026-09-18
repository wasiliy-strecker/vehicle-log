import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/app/app_theme.dart';
import 'package:fahrzeugakte/features/evidence/domain/evidence_export.dart';
import 'package:fahrzeugakte/features/evidence/presentation/evidence_export_card.dart';
import 'package:fahrzeugakte/features/meters/domain/meter.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/home_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_detail_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_form_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_detail_screen.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_history_tile.dart';
import 'package:fahrzeugakte/features/meters/presentation/meter_visuals.dart';

import '../support/contrast_expectations.dart';
import '../support/fakes.dart';
import '../support/reading_fixtures.dart';

void main() {
  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.dark
        ? AppTheme.dark()
        : AppTheme.light();
    for (final type in MeterType.values) {
      testWidgets(
        'pages, dates and reminders have strong contrast: $brightness $type',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 1500));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final book = sampleBook(reminder: _reminder).copyWith(type: type);
          final reading = sampleReading(
            book: book,
            source: ReadingSource.manual,
          );
          await _pump(tester, theme, const HomeScreen(), book: book);
          expectReadable(
            tester,
            find.text('Kilometerstand · 85 km'),
            minimum: 7,
          );
          expectReadable(tester, find.text('Nächste Erinnerung'), minimum: 7);
          expectReadable(
            tester,
            find.byIcon(Icons.schedule_outlined),
            minimum: 7,
          );
          expectReadable(tester, find.byIcon(meterIcon(type)), minimum: 3);
          expectReadableContent(
            tester,
            find.byKey(ValueKey('dashboard-meter-${book.id}')),
          );

          await _pump(
            tester,
            theme,
            MeterDetailScreen(meterId: book.id),
            book: book,
          );
          final header = find.byKey(ValueKey('meter-summary-${book.id}'));
          expectReadable(
            tester,
            find.descendant(
              of: header,
              matching: find.text('Kilometerstand · 85 km'),
            ),
            minimum: 7,
          );
          expectReadableContent(tester, header);
          final pdf = find.ancestor(
            of: find.text('Fahrzeugprotokoll · Fahrzeugverlauf'),
            matching: find.byType(Card),
          );
          expectReadableContent(tester, pdf);

          await _pump(
            tester,
            theme,
            Scaffold(
              body: ReadingHistoryTile(reading: reading, showDelta: false),
            ),
          );
          expectReadable(tester, find.text('85 km'), minimum: 7);
          expectReadable(
            tester,
            find.textContaining('Dokumentiert ·'),
            minimum: 7,
          );
          expectReadable(
            tester,
            find.byIcon(Icons.calendar_month_outlined),
            minimum: 7,
          );
          expectReadableContent(tester, find.byType(ReadingHistoryTile));
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final available in [true, false]) {
      testWidgets(
        'PDF status and actions remain readable: $brightness available=$available',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await _pump(
            tester,
            theme,
            Scaffold(
              body: SingleChildScrollView(
                child: EvidenceExportCard(
                  export: _export,
                  title: 'Fahrzeugprotokoll · Einzelner Eintrag',
                  detail: 'Kilometerstand: 85 km',
                  fileAvailable: available,
                  onTap: () {},
                  onDelete: () {},
                ),
              ),
            ),
            scale: 2,
          );
          expectReadableContent(tester, find.byType(EvidenceExportCard));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'single PDF action and missing photo remain readable: $brightness',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(
          tester,
          theme,
          const ReadingDetailScreen(readingId: 'reading'),
        );
        expectReadableContent(
          tester,
          find.byKey(const ValueKey('single-pdf-action')),
        );
        await _pump(
          tester,
          theme,
          Scaffold(
            body: ReadingHistoryTile(
              reading: sampleReading(),
              showDelta: false,
            ),
          ),
        );
        // File decoding runs outside the fake widget-test clock.
        for (
          var attempt = 0;
          attempt < 20 &&
              find.byIcon(Icons.broken_image_outlined).evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expectReadable(
          tester,
          find.byIcon(Icons.broken_image_outlined),
          minimum: 3,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final mode in ReminderDeliveryMode.values) {
      testWidgets(
        'selected reminder and permission hint remain readable: $brightness $mode',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 2400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final book = sampleBook(
            reminder: ReadingReminderSchedule(
              interval: ReminderInterval.daily,
              day: 1,
              hour: 12,
              minute: 0,
              deliveryMode: mode,
            ),
          );
          await _pump(
            tester,
            theme,
            MeterFormScreen(meterId: book.id),
            book: book,
          );
          for (final name in ['normal', 'punctual']) {
            final card = find.byKey(ValueKey('reminder-mode-$name'));
            await tester.ensureVisible(card);
            await tester.pumpAndSettle();
            expectReadableContent(tester, card);
          }
          if (mode == ReminderDeliveryMode.punctualWithSound) {
            final warning = find.textContaining('Für pünktliche Erinnerungen');
            expectReadable(tester, warning);
            expectReadable(tester, find.text('Alarme & Erinnerungen erlauben'));
            expectReadable(
              tester,
              find.byIcon(Icons.settings_outlined),
              minimum: 3,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget screen, {
  Meter? book,
  double scale = 1,
}) async {
  final meter = book ?? sampleBook();
  final reading = sampleReading(book: meter, source: ReadingSource.manual);
  final reminders = NoopMeterReminderRepository(
    exactAlarmPermissionGranted: false,
  );
  await reminders.schedule(meter, latestReading: reading);
  final router = GoRouter(
    routes: [GoRoute(path: '/', name: 'home', builder: (_, _) => screen)],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        meterRepositoryProvider.overrideWithValue(
          MemoryMeterRepository()..items[meter.id] = meter,
        ),
        meterReadingRepositoryProvider.overrideWithValue(
          MemoryReadingRepository()..items[reading.id] = reading,
        ),
        meterReminderRepositoryProvider.overrideWithValue(reminders),
        evidenceExportRepositoryProvider.overrideWithValue(
          MemoryEvidenceExportRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: theme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _reminder = ReadingReminderSchedule(
  interval: ReminderInterval.daily,
  day: 1,
  hour: 12,
  minute: 0,
);
final _export = EvidenceExportRecord(
  id: 'export',
  meterId: 'book',
  kind: EvidenceExportKind.singleReading,
  readingIds: const ['reading'],
  createdAt: DateTime.utc(2026, 9, 16),
  fileName: 'synthetic.pdf',
  filePath: '/synthetic.pdf',
  pdfSha256: 'a' * 64,
  manifestSha256: 'b' * 64,
);
