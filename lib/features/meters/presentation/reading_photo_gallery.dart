import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';

import '../domain/meter_reading.dart';

class ReadingPhotoGallery extends StatefulWidget {
  const ReadingPhotoGallery({
    super.key,
    required this.photos,
    this.onReplace,
    this.onRemove,
    this.onReorder,
    this.enabled = true,
  });
  final List<ReadingPhotoVersion> photos;
  final ValueChanged<ReadingPhotoVersion>? onReplace;
  final ValueChanged<ReadingPhotoVersion>? onRemove;
  final ValueChanged<List<String>>? onReorder;
  final bool enabled;

  @override
  State<ReadingPhotoGallery> createState() => _ReadingPhotoGalleryState();
}

class _ReadingPhotoGalleryState extends State<ReadingPhotoGallery> {
  String? _draggingId;
  Offset? _pointer;
  Timer? _scrollTimer;

  bool get _sortable => widget.onReorder != null && widget.photos.length > 1;

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
    if (!widget.enabled || !_sortable) return;
    final ids = widget.photos.map((photo) => photo.id).toList();
    final from = ids.indexOf(id);
    if (from < 0 || target < 0 || target >= ids.length || from == target) {
      return;
    }
    ids.insert(target, ids.removeAt(from));
    widget.onReorder!(ids);
  }

  Widget _tile(ReadingPhotoVersion photo, int index) => Column(
    children: [
      Semantics(
        label: 'Foto ${index + 1} von ${widget.photos.length} ansehen',
        button: true,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReadingPhotoViewer(
                photos: List.of(widget.photos),
                initialIndex: index,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: ReadingPhotoImage(photo: photo, thumbnail: true),
            ),
          ),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: Text('Foto ${index + 1}', textAlign: TextAlign.center),
          ),
          if (widget.onReplace != null || widget.onRemove != null || _sortable)
            PopupMenuButton<String>(
              key: ValueKey('photo-menu-${photo.id}'),
              enabled: widget.enabled,
              tooltip: 'Foto ${index + 1} bearbeiten',
              onSelected: (action) {
                switch (action) {
                  case 'replace':
                    widget.onReplace?.call(photo);
                  case 'remove':
                    widget.onRemove?.call(photo);
                  case 'earlier':
                    _move(photo.id, index - 1);
                  case 'later':
                    _move(photo.id, index + 1);
                }
              },
              itemBuilder: (_) => [
                if (_sortable) ...[
                  PopupMenuItem(
                    value: 'earlier',
                    enabled: index > 0,
                    child: const Text('Nach vorne'),
                  ),
                  PopupMenuItem(
                    value: 'later',
                    enabled: index + 1 < widget.photos.length,
                    child: const Text('Nach hinten'),
                  ),
                ],
                if (widget.onReplace != null)
                  const PopupMenuItem(
                    value: 'replace',
                    child: Text('Foto ersetzen'),
                  ),
                if (widget.onRemove != null)
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Foto entfernen'),
                  ),
              ],
            ),
        ],
      ),
    ],
  );

  Widget _draggable(ReadingPhotoVersion photo, int index, double width) =>
      DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            widget.enabled &&
            details.data == _draggingId &&
            details.data != photo.id,
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
            key: ValueKey('photo-drag-${photo.id}'),
            data: photo.id,
            maxSimultaneousDrags: widget.enabled && _draggingId == null ? 1 : 0,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            onDragStarted: () {
              setState(() => _draggingId = photo.id);
              _scrollTimer = Timer.periodic(
                const Duration(milliseconds: 16),
                (_) => _scrollAtEdge(),
              );
            },
            onDragUpdate: (details) => _pointer = details.globalPosition,
            onDragEnd: (_) => _finishDrag(),
            feedback: Transform.translate(
              offset: Offset(-width / 2, -width * 3 / 8),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: width,
                  height: width * 3 / 4,
                  child: ReadingPhotoImage(photo: photo, thumbnail: true),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: .3, child: _tile(photo, index)),
            child: _tile(photo, index),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const Text('Keine aktuellen Fotos');
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = widget.photos.length == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (index, photo) in widget.photos.indexed)
              SizedBox(
                key: _sortable ? ValueKey(photo.id) : null,
                width: width,
                child: _sortable
                    ? _draggable(photo, index, width)
                    : _tile(photo, index),
              ),
          ],
        );
      },
    );
  }
}

class ReadingPhotoImage extends StatelessWidget {
  const ReadingPhotoImage({
    super.key,
    required this.photo,
    this.thumbnail = false,
  });
  final ReadingPhotoVersion photo;
  final bool thumbnail;
  @override
  Widget build(BuildContext context) => Image.file(
    File(photo.path),
    fit: BoxFit.contain,
    cacheWidth: thumbnail ? 600 : null,
    errorBuilder: (_, _, _) => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined),
              Text('Foto nicht verfügbar', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

class ReadingPhotoViewer extends StatefulWidget {
  const ReadingPhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  });
  final List<ReadingPhotoVersion> photos;
  final int initialIndex;
  @override
  State<ReadingPhotoViewer> createState() => _ReadingPhotoViewerState();
}

class _ReadingPhotoViewerState extends State<ReadingPhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Foto ${_index + 1} von ${widget.photos.length}'),
    ),
    body: PageView.builder(
      controller: _pages,
      itemCount: widget.photos.length,
      onPageChanged: (index) => setState(() => _index = index),
      itemBuilder: (_, index) => InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(child: ReadingPhotoImage(photo: widget.photos[index])),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'Vorheriges Foto',
            onPressed: _index == 0
                ? null
                : () => _pages.previousPage(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  ),
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${_index + 1} / ${widget.photos.length}'),
          IconButton(
            tooltip: 'Nächstes Foto',
            onPressed: _index + 1 == widget.photos.length
                ? null
                : () => _pages.nextPage(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ),
  );
}

class ReadingPhotoEditor extends StatelessWidget {
  const ReadingPhotoEditor({
    super.key,
    required this.photos,
    required this.busy,
    required this.onCamera,
    required this.onGallery,
    required this.onReplace,
    required this.onRemove,
    this.onReorder,
    this.progress = '',
    this.correction = false,
  });
  final List<ReadingPhotoVersion> photos;
  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ValueChanged<ReadingPhotoVersion> onReplace;
  final ValueChanged<ReadingPhotoVersion> onRemove;
  final ValueChanged<List<String>>? onReorder;
  final String progress;
  final bool correction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Aktuelle Fotos (${photos.length})',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (photos.length > 1 && onReorder != null) ...[
            const SizedBox(height: 6),
            const Text(
              'Zum Sortieren ein Foto länger gedrückt halten und verschieben.',
            ),
          ],
          const SizedBox(height: 10),
          ReadingPhotoGallery(
            photos: photos,
            enabled: !busy,
            onReplace: onReplace,
            onRemove: onRemove,
            onReorder: onReorder,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onCamera,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(
              photos.isEmpty ? 'Foto aufnehmen' : 'Weiteres Foto aufnehmen',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : onGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text(
              'Fotos aus Galerie hinzufügen',
              textAlign: TextAlign.center,
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              progress.isEmpty ? 'Fotos werden vorbereitet …' : progress,
              textAlign: TextAlign.center,
            ),
          ],
          if (correction) ...[
            const SizedBox(height: 10),
            const Text(
              'Ersetzte und entfernte Fotos bleiben nach dem Speichern im Korrekturverlauf erhalten.',
            ),
          ],
        ],
      ),
    ),
  );
}

Future<ReadingSource?> choosePhotoReplacementSource(BuildContext context) =>
    showModalBottomSheet<ReadingSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Foto ersetzen')),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Neu fotografieren'),
              onTap: () => Navigator.pop(context, ReadingSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Aus Galerie wählen'),
              onTap: () => Navigator.pop(context, ReadingSource.gallery),
            ),
          ],
        ),
      ),
    );
