import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/widgets/app_snack_bar.dart';
import '../../../core/files/pdf_limits.dart';
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

  Future<void> _reorder(BuildContext context, List<String> ids) async {
    if (!enabled || session.busy) return;
    final byId = {
      for (final document in session.documents) document.id: document,
    };
    if (ids.length != byId.length ||
        ids.toSet().length != byId.length ||
        ids.any((id) => !byId.containsKey(id))) {
      return;
    }
    await _run(
      context,
      () =>
          session.changeDocuments([for (final id in ids) byId[id]!], fields()),
    );
  }

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
        final message = error is FormatException
            ? error.message
            : 'Bitte versuche es erneut.';
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message: 'Dokument konnte nicht verarbeitet werden: $message',
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
          const SizedBox(height: 6),
          Text(
            '${session.documentPages} von ${PdfLimits.entryPages} PDF-Seiten · '
            '${(session.documentBytes / 1000000).toStringAsFixed(1)} von 50 MB',
          ),
          const Text('Maximal 25 MB je PDF'),
          if (session.documentPages > PdfLimits.entryPages ||
              session.documentBytes > PdfLimits.entryBytes)
            const Text(
              'Bereits gespeicherte größere Anhänge bleiben erhalten.',
            ),
          if (session.documents.length > 1) ...[
            const SizedBox(height: 6),
            const Text(
              'Zum Sortieren eine PDF länger gedrückt halten und verschieben.',
            ),
          ],
          const SizedBox(height: 10),
          if (session.documents.isEmpty)
            const Text('Keine aktuellen PDFs')
          else
            ReadingDocuments(
              documents: session.documents,
              embedded: true,
              enabled: enabled && !session.busy,
              onReorder: (ids) => _reorder(context, ids),
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
            onPressed:
                enabled && !session.busy && !session.documentBudget().exhausted
                ? () => _add(context)
                : null,
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
    this.onReorder,
    this.enabled = true,
    this.embedded = false,
  });
  final List<ReadingDocument> documents;
  final void Function(ReadingDocument, String)? onAction;
  final ValueChanged<List<String>>? onReorder;
  final bool enabled;
  final bool embedded;

  @override
  Widget build(BuildContext context) =>
      onReorder != null && documents.length > 1
      ? _SortableReadingDocuments(
          documents: documents,
          enabled: enabled,
          onReorder: onReorder!,
          itemBuilder: (document, index) =>
              _buildDocument(context, index, document),
        )
      : Column(
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
              key: ValueKey('document-menu-${document.id}'),
              enabled: enabled,
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

class _SortableReadingDocuments extends StatefulWidget {
  const _SortableReadingDocuments({
    required this.documents,
    required this.enabled,
    required this.onReorder,
    required this.itemBuilder,
  });

  final List<ReadingDocument> documents;
  final bool enabled;
  final ValueChanged<List<String>> onReorder;
  final Widget Function(ReadingDocument, int) itemBuilder;

  @override
  State<_SortableReadingDocuments> createState() =>
      _SortableReadingDocumentsState();
}

class _SortableReadingDocumentsState extends State<_SortableReadingDocuments> {
  String? _draggingId;
  Offset? _pointer;
  Timer? _scrollTimer;

  @override
  void didUpdateWidget(covariant _SortableReadingDocuments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _finishDrag();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _finishDrag() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _pointer = null;
    if (mounted && _draggingId != null) setState(() => _draggingId = null);
  }

  void _scrollAtEdge() {
    if (!mounted || !widget.enabled || _pointer == null) return;
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null || box is! RenderBox || !box.hasSize) return;
    final position = scrollable.position;
    final local = box.globalToLocal(_pointer!);
    const edge = 72.0;
    final double delta;
    if (local.dy < edge) {
      delta = -12 * ((edge - local.dy) / edge).clamp(0, 1);
    } else if (local.dy > box.size.height - edge) {
      delta = 12 * ((local.dy - box.size.height + edge) / edge).clamp(0, 1);
    } else {
      return;
    }
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next != position.pixels) position.jumpTo(next);
  }

  void _move(String id, int target) {
    if (!widget.enabled) return;
    final ids = widget.documents.map((document) => document.id).toList();
    final from = ids.indexOf(id);
    if (from < 0 || target < 0 || target >= ids.length || from == target) {
      return;
    }
    ids.insert(target, ids.removeAt(from));
    widget.onReorder(ids);
  }

  Widget _draggable(ReadingDocument document, int index, double width) =>
      DragTarget<String>(
        key: ValueKey(document.id),
        onWillAcceptWithDetails: (details) =>
            widget.enabled &&
            details.data == _draggingId &&
            details.data != document.id,
        onAcceptWithDetails: (details) => _move(details.data, index),
        builder: (context, candidates, rejected) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              width: 2,
              color: candidates.isEmpty
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          child: LongPressDraggable<String>(
            key: ValueKey('document-drag-${document.id}'),
            data: document.id,
            maxSimultaneousDrags: widget.enabled && _draggingId == null ? 1 : 0,
            onDragStarted: () {
              setState(() => _draggingId = document.id);
              _scrollTimer = Timer.periodic(
                const Duration(milliseconds: 16),
                (_) => _scrollAtEdge(),
              );
            },
            onDragUpdate: (details) => _pointer = details.globalPosition,
            onDragEnd: (_) => _finishDrag(),
            feedback: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: width,
                child: widget.itemBuilder(document, index),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: .3,
              child: widget.itemBuilder(document, index),
            ),
            child: widget.itemBuilder(document, index),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        for (final (index, document) in widget.documents.indexed)
          _draggable(document, index, constraints.maxWidth),
      ],
    ),
  );
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
