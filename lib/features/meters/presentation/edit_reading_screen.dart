import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../app/widgets/app_snack_bar.dart';
import '../../../app/widgets/confirm_dialog.dart';
import '../../../core/files/meter_photo_repository.dart';
import '../application/reading_photo_session.dart';
import 'reading_photo_gallery.dart';
import 'reading_documents.dart';
import '../domain/meter_reading.dart';
import '../domain/reading_value.dart';
import 'editable_reading_time_card.dart';
import 'care_activity_field.dart';

class EditReadingScreen extends ConsumerWidget {
  const EditReadingScreen({super.key, required this.readingId});

  final String readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(readingByIdProvider(readingId))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const Scaffold(
            body: Center(child: Text('Eintrag konnte nicht geladen werden.')),
          ),
          data: (reading) => reading == null
              ? const Scaffold(
                  body: Center(child: Text('Eintrag nicht gefunden.')),
                )
              : _EditReadingForm(reading: reading),
        );
  }
}

class _EditReadingForm extends ConsumerStatefulWidget {
  const _EditReadingForm({required this.reading});

  final MeterReading reading;

  @override
  ConsumerState<_EditReadingForm> createState() => _EditReadingFormState();
}

class _EditReadingFormState extends ConsumerState<_EditReadingForm> {
  final _formKey = GlobalKey<FormState>();
  final _workshop = TextEditingController();
  final _cost = TextEditingController();
  late final TextEditingController _value;
  late final TextEditingController _note;
  late final ReadingPhotoSession _photoSession;
  late DateTime _capturedAt;
  late final TextEditingController _activity;
  bool get _processingPhoto => _photoSession.busy;
  bool _saving = false;
  bool _discardDialogOpen = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _photoSession = ReadingPhotoSession(
      route: '/reading/${widget.reading.id}/edit',
      original: widget.reading,
      repository: ref.read(meterPhotoCaptureRepositoryProvider),
      documentRepository: ref.read(documentRepositoryProvider),
      store: ref.read(photoDraftStoreProvider),
      readings: ref.read(meterReadingRepositoryProvider),
    )..addListener(_photosChanged);
    _activity = TextEditingController(text: widget.reading.activityLabel);
    _value = TextEditingController(
      text: widget.reading.hasMeasurement
          ? widget.reading.value.displayText
          : '',
    );
    _note = TextEditingController(text: widget.reading.note);
    _workshop.text = widget.reading.workshop;
    _cost.text = costInput(widget.reading.costCents);
    _capturedAt = widget.reading.capturedAt.toLocal();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePhotoDraft());
  }

  @override
  void dispose() {
    _photoSession.removeListener(_photosChanged);
    unawaited(_photoSession.close().catchError((Object _) {}));
    _activity.dispose();
    _value.dispose();
    _note.dispose();
    _workshop.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
        title: const Text('Eintrag bearbeiten'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildPhotoEditor(context),
            ReadingDocumentEditor(
              session: _photoSession,
              fields: () => _draftFields,
              enabled: !_saving && !_processingPhoto,
            ),
            const SizedBox(height: 14),
            CareActivityField(
              controller: _activity,
              enabled: !_saving && !_processingPhoto,
              autofocus: false,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _value,
              decoration: InputDecoration(
                labelText: 'Kilometerstand (optional)',
                suffixText: widget.reading.meter.unit,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              validator: (value) =>
                  (value ?? '').trim().isNotEmpty &&
                      ReadingValue.tryParseEdit(
                            value ?? '',
                            widget.reading.value,
                          ) ==
                          null
                  ? 'Bitte eine ganze Zahl ab 0 eingeben.'
                  : null,
            ),
            const SizedBox(height: 12),
            VehicleEntryFields(
              workshop: _workshop,
              cost: _cost,
              enabled: !_saving && !_photoSession.busy,
              onChanged: () => setState(() {}),
            ),
            EditableReadingTimeCard(value: _capturedAt, onPressed: _pickDate),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Notiz'),
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving || _processingPhoto ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Änderungen speichern'),
            ),
          ],
        ),
      ),
    );
    return PopScope<void>(
      canPop:
          _allowPop || (!_hasUnsavedChanges && !_processingPhoto && !_saving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: scaffold,
    );
  }

  bool get _hasUnsavedChanges =>
      _activity.text.trim() != widget.reading.activityLabel ||
      _workshop.text.trim() != widget.reading.workshop ||
      _cost.text.trim() != costInput(widget.reading.costCents) ||
      _value.text.trim() !=
          (widget.reading.hasMeasurement
              ? widget.reading.value.displayText
              : '') ||
      _note.text.trim() != widget.reading.note ||
      _capturedAt != widget.reading.capturedAt.toLocal() ||
      _photoSession.changed;

  Future<void> _handleBack() async {
    if (_saving || _processingPhoto || _discardDialogOpen) return;
    FocusScope.of(context).unfocus();
    if (!_hasUnsavedChanges) {
      _leaveForm();
      return;
    }

    _discardDialogOpen = true;
    final discard = await confirmDiscardChanges(
      context,
      title: 'Änderungen verwerfen?',
      message:
          'Deine Änderungen an diesem Eintrag wurden noch nicht gespeichert.',
      discardLabel: 'Änderungen verwerfen',
    );
    _discardDialogOpen = false;
    if (!mounted || !discard) return;
    try {
      await _photoSession.discard();
      if (mounted) await _leaveWithoutGuard();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message: 'Änderungen konnten nicht verworfen werden: $error',
          ),
        );
      }
    }
  }

  Future<void> _leaveWithoutGuard() async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _leaveForm();
  }

  void _leaveForm() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed(
        'readingDetail',
        pathParameters: {'id': widget.reading.id},
      );
    }
  }

  Widget _buildPhotoEditor(BuildContext context) => ReadingPhotoEditor(
    photos: _photoSession.photos,
    busy: _saving || _processingPhoto,
    progress: _photoSession.progress,
    onCamera: () => _capturePhoto(ReadingSource.camera),
    onGallery: () => _capturePhoto(ReadingSource.gallery),
    onReplace: _replacePhoto,
    onRemove: _removePhoto,
    onReorder: _reorderPhotos,
  );

  void _photosChanged() {
    if (mounted) setState(() {});
  }

  Map<String, dynamic> get _draftFields => {
    'value': _value.text,
    'hasMeasurement': _value.text.trim().isNotEmpty,
    'activityText': _activity.text,
    'note': _note.text,
    'workshop': _workshop.text,
    'cost': _cost.text,
    'capturedAt': _capturedAt.toIso8601String(),
  };

  void _showPhotoFailures(PhotoImportResult result) {
    if (!mounted || result.failures.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      AppSnackBar(
        message:
            '${result.photos.length} Fotos hinzugefügt. Nicht verarbeitet: ${result.failures.join(', ')}',
      ),
    );
  }

  Future<void> _capturePhoto(
    ReadingSource source, {
    String? replacementId,
  }) async {
    if (!mounted || _processingPhoto || _saving) return;
    FocusScope.of(context).unfocus();
    try {
      final result = await _photoSession.capture(
        source,
        formFields: _draftFields,
        replacementId: replacementId,
      );
      _showPhotoFailures(result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message: 'Fotos konnten nicht hinzugefügt werden: $error',
          ),
        );
      }
    }
  }

  Future<void> _replacePhoto(ReadingPhotoVersion photo) async {
    final source = await choosePhotoReplacementSource(context);
    if (source != null && mounted) {
      await _capturePhoto(source, replacementId: photo.id);
    }
  }

  Future<void> _removePhoto(ReadingPhotoVersion photo) async {
    try {
      await _photoSession.removePhoto(photo.id, _draftFields);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(message: 'Foto konnte nicht entfernt werden: $error'),
        );
      }
    }
  }

  Future<void> _reorderPhotos(List<String> ids) async {
    try {
      await _photoSession.reorderPhotos(ids, _draftFields);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message: 'Fotoreihenfolge konnte nicht gespeichert werden: $error',
          ),
        );
      }
    }
  }

  Future<void> _restorePhotoDraft() async {
    try {
      final result = await _photoSession.restore().whenComplete(() {
        if (!mounted) return;
        final fields = _photoSession.fields;
        if (fields.isNotEmpty) {
          setState(() {
            _value.text = fields['hasMeasurement'] == false
                ? ''
                : fields['value'] as String;
            _activity.text = activityTextFromDraft(
              fields,
              widget.reading.activityLabel,
            );
            _note.text = fields['note'] as String;
            _workshop.text = fields['workshop'] as String? ?? '';
            _cost.text = fields['cost'] as String? ?? '';
            _capturedAt = DateTime.parse(fields['capturedAt'] as String);
          });
        }
      });
      _showPhotoFailures(result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message:
                'Foto-Zwischenstand konnte nicht wiederhergestellt werden: $error',
          ),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final date = await showDatePicker(
      context: context,
      initialDate: _capturedAt,
      firstDate: firstSelectableReadingDate,
      lastDate: lastSelectableReadingDate,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_capturedAt),
    );
    if (time != null) {
      setState(() {
        _capturedAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // A long photo list can scroll the form field out of the widget tree.
    if (_activity.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(AppSnackBar(message: 'Bitte eine Aktivität angeben.'));
      return;
    }
    final activity = CareActivitySelection.fromText(_activity.text);
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(meterReadingServiceProvider)
          .update(
            existing: widget.reading,
            activity: activity.activity,
            customActivityLabel: activity.customActivityLabel,
            hasMeasurement: _value.text.trim().isNotEmpty,
            value: _value.text.trim().isEmpty
                ? ReadingValue.tryParseWhole('0')!
                : ReadingValue.tryParseEdit(_value.text, widget.reading.value)!,
            capturedAt: _capturedAt,
            note: _note.text,
            photos: List.of(_photoSession.photos),
            documents: List.of(_photoSession.documents),
            workshop: _workshop.text,
            costCents: parseCostCents(_cost.text),
            clearCost: _cost.text.trim().isEmpty,
          );
      final changed = !identical(updated, widget.reading);
      ref.invalidate(readingByIdProvider(widget.reading.id));
      await _photoSession.committed();
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        await _leaveWithoutGuard();
        if (messenger.mounted) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              AppSnackBar(
                message: changed
                    ? 'Änderungen gespeichert.'
                    : 'Keine Änderungen vorhanden.',
              ),
            );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message: 'Änderungen konnten nicht gespeichert werden: $error',
          ),
        );
        setState(() => _saving = false);
      }
    }
  }
}
