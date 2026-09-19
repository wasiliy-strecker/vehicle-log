import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/widgets/app_snack_bar.dart';
import '../application/reading_photo_session.dart';
import '../domain/reading_document.dart';

class ReadingDocumentEditor extends StatelessWidget {
  const ReadingDocumentEditor({
    super.key,
    required this.session,
    required this.fields,
    this.enabled = true,
  });
  final ReadingPhotoSession session;
  final Map<String, dynamic> Function() fields;
  final bool enabled;

  Future<void> _add(BuildContext context, {String? replacementId}) async {
    final scan = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('PDF auswählen'),
              subtitle:
                  replacementId == null &&
                      !kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android
                  ? const Text(
                      'Mehrere PDFs: Erste Datei länger gedrückt halten, dann weitere auswählen.',
                    )
                  : null,
              onTap: () => Navigator.pop(context, false),
            ),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Dokument scannen'),
                subtitle: const Text('Mehrere Seiten als eine PDF erfassen'),
                onTap: () => Navigator.pop(context, true),
              ),
          ],
        ),
      ),
    );
    if (scan == null || !context.mounted) return;
    await _run(context, () async {
      final result = await session.captureDocuments(
        scan: scan,
        formFields: fields(),
        replacementId: replacementId,
      );
      if (result.failures.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message: 'Nicht hinzugefügt: ${result.failures.join(', ')}',
          ),
        );
      }
    });
  }

  Future<void> _run(BuildContext context, Future<void> Function() work) async {
    try {
      await work();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message: 'Dokument konnte nicht verarbeitet werden: $error',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Aktuelle PDFs (${session.documents.length})',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (session.documents.isEmpty)
            const Text('Keine aktuellen PDFs')
          else
            ReadingDocuments(
              documents: session.documents,
              embedded: true,
              onAction: !enabled || session.busy
                  ? null
                  : (doc, action) async {
                      if (action == 'replace') {
                        await _add(context, replacementId: doc.id);
                        return;
                      }
                      final next = List<ReadingDocument>.of(session.documents);
                      final index = next.indexWhere((d) => d.id == doc.id);
                      if (action == 'remove') {
                        next.removeAt(index);
                      }
                      if (action == 'earlier' && index > 0) {
                        next.insert(index - 1, next.removeAt(index));
                      }
                      if (action == 'later' && index + 1 < next.length) {
                        next.insert(index + 1, next.removeAt(index));
                      }
                      await _run(
                        context,
                        () => session.changeDocuments(next, fields()),
                      );
                    },
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: enabled && !session.busy ? () => _add(context) : null,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text(
              'PDF auswählen/scannen',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );
}

class ReadingDocuments extends StatelessWidget {
  const ReadingDocuments({
    super.key,
    required this.documents,
    this.onAction,
    this.embedded = false,
  });
  final List<ReadingDocument> documents;
  final void Function(ReadingDocument, String)? onAction;
  final bool embedded;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (index, document) in documents.indexed)
        _buildDocument(context, index, document),
    ],
  );

  Widget _buildDocument(
    BuildContext context,
    int index,
    ReadingDocument document,
  ) {
    final tile = ListTile(
      contentPadding: embedded ? EdgeInsets.zero : null,
      leading: const Icon(Icons.picture_as_pdf_outlined),
      title: Text(document.fileName),
      subtitle: Text(
        '${document.pageCount} ${document.pageCount == 1 ? 'Seite' : 'Seiten'} · ${document.source == DocumentSource.scanned ? 'Gescannt' : 'Importiert'}',
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _DocumentViewer(document: document),
        ),
      ),
      trailing: onAction == null
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Dokument bearbeiten',
              onSelected: (value) => onAction!(document, value),
              itemBuilder: (_) => [
                if (documents.length > 1) ...[
                  PopupMenuItem(
                    value: 'earlier',
                    enabled: index > 0,
                    child: const Text('Nach vorne'),
                  ),
                  PopupMenuItem(
                    value: 'later',
                    enabled: index + 1 < documents.length,
                    child: const Text('Nach hinten'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'replace',
                  child: Text('Dokument ersetzen'),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Dokument entfernen'),
                ),
              ],
            ),
    );
    return embedded ? tile : Card(child: tile);
  }
}

class _DocumentViewer extends StatelessWidget {
  const _DocumentViewer({required this.document});
  final ReadingDocument document;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(document.fileName),
      actions: [
        IconButton(
          tooltip: 'PDF teilen',
          icon: const Icon(Icons.share_outlined),
          onPressed: () async {
            try {
              await SharePlus.instance.share(
                ShareParams(
                  files: [XFile(document.path, mimeType: 'application/pdf')],
                  fileNameOverrides: [document.fileName],
                ),
              );
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  AppSnackBar(
                    message: 'PDF konnte nicht geteilt werden: $error',
                  ),
                );
              }
            }
          },
        ),
      ],
    ),
    body: PdfViewer.file(
      document.path,
      params: PdfViewerParams(
        errorBannerBuilder: (context, error, stackTrace, documentRef) =>
            const Center(child: Text('Die PDF konnte nicht geöffnet werden.')),
      ),
    ),
  );
}

class VehicleEntryFields extends StatelessWidget {
  const VehicleEntryFields({
    super.key,
    required this.workshop,
    required this.cost,
    required this.onChanged,
    this.enabled = true,
  });
  final TextEditingController workshop;
  final TextEditingController cost;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextFormField(
        controller: workshop,
        enabled: enabled,
        decoration: const InputDecoration(
          labelText: 'Werkstatt (optional)',
          hintText: 'z. B. Autohaus Müller',
        ),
        onChanged: (_) => onChanged(),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: cost,
        enabled: enabled,
        decoration: const InputDecoration(
          labelText: 'Kosten (optional)',
          suffixText: '€',
          hintText: 'z. B. 249,90',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => onChanged(),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        validator: (value) {
          try {
            parseCostCents(value ?? '');
            return null;
          } on FormatException catch (error) {
            return error.message;
          }
        },
      ),
      const SizedBox(height: 12),
    ],
  );
}
