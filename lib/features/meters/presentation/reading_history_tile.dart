import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_io/io.dart';

import '../../../core/utils/formatters.dart';
import '../domain/meter_reading.dart';
import 'meter_visuals.dart';

class ReadingHistoryTile extends StatelessWidget {
  const ReadingHistoryTile({
    super.key,
    this.onTap,
    required this.reading,
    required this.showDelta,
    this.previous,
  });

  final VoidCallback? onTap;
  final MeterReading reading;
  final MeterReading? previous;
  final bool showDelta;

  @override
  Widget build(BuildContext context) {
    final meterAccent = meterColor(
      reading.meter.type,
      Theme.of(context).brightness,
    );
    final sameUnit =
        previous == null || previous!.meter.unit == reading.meter.unit;
    final delta =
        !showDelta ||
            previous == null ||
            !reading.canCompareGrowthWith(previous!)
        ? null
        : reading.value.difference(previous!.value).germanFormatted;
    return Card(
      key: ValueKey('reading-card-${reading.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            onTap ??
            () => context.pushNamed(
              'readingDetail',
              pathParameters: {'id': reading.id},
            ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label:
                    'Dokumentiert am ${formatDateTime(reading.capturedAt)} Uhr',
                child: SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    key: ValueKey('reading-date-badge-${reading.id}'),
                    decoration: BoxDecoration(
                      color: meterAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            size: 17,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Dokumentiert · ${formatDateTime(reading.capturedAt)} Uhr',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _ReadingPhotoThumbnail(reading: reading),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reading.activityLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reading.measurementText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        if (showDelta && previous != null && !sameUnit) ...[
                          const SizedBox(height: 8),
                          const Text('Einheit seit diesem Eintrag gewechselt'),
                        ] else if (delta != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${previous!.value.displayText} → ${reading.value.displayText} = $delta ${reading.meter.unit} Differenz',
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (reading.note.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reading.note.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingPhotoThumbnail extends StatelessWidget {
  const _ReadingPhotoThumbnail({required this.reading});

  final MeterReading reading;

  @override
  Widget build(BuildContext context) {
    final fallbackColor = Theme.of(context).colorScheme.primaryContainer;
    return Semantics(
      label: reading.hasPhoto
          ? '${reading.currentPhotos.length} Fotos: ${reading.summary}'
          : 'Manuell erfasst: ${reading.summary}',
      image: reading.hasPhoto,
      child: ClipRRect(
        key: ValueKey('reading-thumbnail-${reading.id}'),
        borderRadius: BorderRadius.circular(14),
        child: SizedBox.square(
          dimension: 92,
          child: !reading.hasPhoto
              ? ColoredBox(
                  color: fallbackColor,
                  child: Icon(
                    Icons.edit_note_outlined,
                    size: 30,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(reading.currentPhotos.first.path),
                      fit: BoxFit.cover,
                      cacheWidth: 240,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: fallbackColor,
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 30,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    if (reading.currentPhotos.length > 1)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              '${reading.currentPhotos.length} Fotos',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
