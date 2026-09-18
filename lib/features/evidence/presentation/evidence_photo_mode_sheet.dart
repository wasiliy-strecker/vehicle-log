import 'package:flutter/material.dart';

import '../domain/evidence_export.dart';

Future<EvidencePhotoMode?> showEvidencePhotoModeSheet(
  BuildContext context, {
  required EvidenceExportKind kind,
  required bool hasCurrentPhotos,
}) {
  return showModalBottomSheet<EvidencePhotoMode>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PDF-Inhalt wählen',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Wähle, welche Inhalte deine PDF enthalten soll.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _PhotoModeTile(
              mode: EvidencePhotoMode.withoutPhotos,
              kind: kind,
              icon: Icons.description_outlined,
              description:
                  'Einträge, Werkstatt, Kosten, Notizen und Dokumentenliste – ohne Anhänge.',
            ),
            const SizedBox(height: 8),
            _PhotoModeTile(
              mode: EvidencePhotoMode.currentPhotos,
              enabled: hasCurrentPhotos,
              kind: kind,
              icon: Icons.photo_outlined,
              description: kind == EvidenceExportKind.singleReading
                  ? 'Enthält alle aktuellen Fotos und alle Seiten der PDF-Dokumente.'
                  : 'Enthält pro Eintrag alle aktuellen Fotos und PDF-Dokumente.',
            ),
          ],
        ),
      ),
    ),
  );
}

class _PhotoModeTile extends StatelessWidget {
  const _PhotoModeTile({
    required this.mode,
    required this.kind,
    required this.icon,
    required this.description,
    this.enabled = true,
  });

  final EvidencePhotoMode mode;
  final EvidenceExportKind kind;
  final IconData icon;
  final String description;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: ValueKey('evidence-photo-mode-${mode.name}'),
        enabled: enabled,
        leading: Icon(
          icon,
          color: enabled ? colors.primary : Theme.of(context).disabledColor,
        ),
        title: Text(
          mode.labelFor(kind),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          enabled ? description : 'Keine aktuellen Fotos oder PDFs vorhanden.',
          style: enabled ? null : TextStyle(color: colors.onSurfaceVariant),
        ),
        trailing: enabled ? const Icon(Icons.chevron_right) : null,
        onTap: enabled ? () => Navigator.pop(context, mode) : null,
      ),
    );
  }
}
