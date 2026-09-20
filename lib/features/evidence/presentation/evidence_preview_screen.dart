import 'dart:typed_data';
import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/widgets/app_actions.dart';
import '../../../app/widgets/app_snack_bar.dart';
import '../application/evidence_report_service.dart';

class EvidencePreviewScreen extends StatefulWidget {
  const EvidencePreviewScreen({super.key, required this.report});
  final GeneratedEvidenceReport report;

  @override
  State<EvidencePreviewScreen> createState() => _EvidencePreviewScreenState();
}

class _EvidencePreviewScreenState extends State<EvidencePreviewScreen> {
  int _selected = 0;
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _bytes = File(widget.report.records[_selected].filePath).readAsBytes();
  }

  @override
  void didUpdateWidget(covariant EvidencePreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report != widget.report) {
      _selected = 0;
      _load();
    }
  }

  Future<void> _share({bool all = false}) async {
    try {
      final records = all
          ? widget.report.records
          : [widget.report.records[_selected]];
      await SharePlus.instance.share(
        ShareParams(
          title: 'Fahrzeugprotokoll',
          text: 'Fahrzeugprotokoll aus Fahrzeugakte',
          files: [
            for (final record in records)
              XFile(
                record.filePath,
                mimeType: 'application/pdf',
                name: record.fileName,
              ),
          ],
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(message: 'Die PDF-Dateien konnten nicht geteilt werden.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.report.records;
    final record = records[_selected];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          records.length > 1
              ? 'Fahrzeugprotokoll · ${records.length} Teile'
              : 'Fahrzeugprotokoll',
        ),
      ),
      body: Column(
        children: [
          if (records.length > 1)
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<int>(
                initialValue: _selected,
                decoration: const InputDecoration(
                  labelText: 'PDF-Teil auswählen',
                ),
                items: [
                  for (var i = 0; i < records.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('Teil ${i + 1} von ${records.length}'),
                    ),
                ],
                onChanged: (index) {
                  if (index == null || index == _selected) return;
                  setState(() {
                    _selected = index;
                    _load();
                  });
                },
              ),
            ),
          Expanded(
            child: FutureBuilder<Uint8List>(
              future: _bytes,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Die PDF-Datei konnte nicht geöffnet werden.'),
                  );
                }
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return PdfPreview(
                  key: ValueKey(record.id),
                  build: (_) async => snapshot.requireData,
                  pdfFileName: record.fileName,
                  allowSharing: false,
                  allowPrinting: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppActionRow(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await Printing.layoutPdf(
                              name: record.fileName,
                              onLayout: (_) =>
                                  File(record.filePath).readAsBytes(),
                            );
                          } on Object {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                AppSnackBar(
                                  message:
                                      'Die PDF konnte nicht gedruckt werden.',
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Drucken'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _share(),
                        icon: const Icon(Icons.ios_share_outlined),
                        label: Text(
                          records.length > 1 ? 'Diesen Teil teilen' : 'Teilen',
                        ),
                      ),
                    ],
                  ),
                  if (records.length > 1) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _share(all: true),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Alle teilen'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
