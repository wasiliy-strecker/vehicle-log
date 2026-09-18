import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../app/widgets/app_snack_bar.dart';
import '../../../app/widgets/confirm_dialog.dart';
import '../../../core/files/meter_photo_repository.dart';
import '../domain/meter.dart';
import '../application/reading_photo_session.dart';
import 'reading_photo_gallery.dart';
import 'reading_documents.dart';
import '../domain/meter_reading.dart';
import '../domain/reading_value.dart';
import 'editable_reading_time_card.dart';
import 'care_activity_field.dart';
import 'meter_photo_examples.dart';
import 'meter_unit_field.dart';

class CaptureReadingScreen extends ConsumerStatefulWidget {
  const CaptureReadingScreen({super.key, required this.meterId});

  final String meterId;

  @override
  ConsumerState<CaptureReadingScreen> createState() =>
      _CaptureReadingScreenState();
}

class _CaptureReadingScreenState extends ConsumerState<CaptureReadingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _workshop = TextEditingController();
  final _cost = TextEditingController();
  final _value = TextEditingController();
  final _note = TextEditingController();
  late final ReadingPhotoSession _photoSession;
  bool _photoEntry = false;
  late DateTime _initialCapturedAt;
  late DateTime _capturedAt;
  bool _saving = false;
  bool get _working => _saving || _photoSession.busy;
  bool _discardDialogOpen = false;
  bool _allowPop = false;
  bool _manual = false;
  final _activity = TextEditingController();
  String? _selectedUnit;

  @override
  void initState() {
    super.initState();
    _initialCapturedAt = DateTime.now();
    _capturedAt = _initialCapturedAt;
    _photoSession = ReadingPhotoSession(
      route: '/meter/${widget.meterId}/capture',
      repository: ref.read(meterPhotoCaptureRepositoryProvider),
      documentRepository: ref.read(documentRepositoryProvider),
      store: ref.read(photoDraftStoreProvider),
      readings: ref.read(meterReadingRepositoryProvider),
    )..addListener(_photosChanged);
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
    return ref
        .watch(meterByIdProvider(widget.meterId))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const Scaffold(
            body: Center(child: Text('Fahrzeug konnte nicht geladen werden.')),
          ),
          data: (meter) => meter == null
              ? const Scaffold(
                  body: Center(child: Text('Fahrzeug nicht gefunden.')),
                )
              : _buildContent(meter),
        );
  }

  Widget _buildContent(Meter meter) {
    final selectedUnit = _selectedUnit ?? meter.unit;

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
        title: const Text('Eintrag erfassen'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          key: ValueKey(_isEnteringReading),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (!_isEnteringReading) ...[
              const _CaptureGuidance(),
              const SizedBox(height: 14),
              MeterPhotoExamplesButton(enabled: !_working),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _working
                    ? null
                    : () => setState(() {
                        _manual = true;
                        _initialCapturedAt = DateTime.now();
                        _capturedAt = _initialCapturedAt;
                      }),
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Ohne Foto erfassen'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _capture(ReadingSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Fahrzeug fotografieren'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _capture(ReadingSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Fotos aus Galerie'),
              ),
              const SizedBox(height: 12),
              ReadingDocumentEditor(
                session: _photoSession,
                fields: () => _draftFields,
                enabled: !_working,
              ),
              const SizedBox(height: 12),
              if (_working) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                Center(child: Text(_photoSession.progress)),
              ],
            ] else ...[
              CareActivityField(
                controller: _activity,
                autofocus: _manual,
                enabled: !_working,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              ReadingPhotoEditor(
                photos: _photoSession.photos,
                busy: _working,
                progress: _photoSession.progress,
                onCamera: () => _capture(ReadingSource.camera),
                onGallery: () => _capture(ReadingSource.gallery),
                onReplace: _replacePhoto,
                onRemove: _removePhoto,
                onReorder: _reorderPhotos,
              ),
              ReadingDocumentEditor(
                session: _photoSession,
                fields: () => _draftFields,
                enabled: !_working,
              ),
              const SizedBox(height: 12),
              if (!_manual) ...[
                MeterUnitField(
                  meterType: meter.type,
                  value: selectedUnit,
                  labelText: 'Einheit des Eintrags',
                  enabled: !_working,
                  onChanged: (value) => setState(() => _selectedUnit = value),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _value,
                decoration: InputDecoration(
                  labelText: 'Kilometerstand (optional)',
                  suffixText: selectedUnit,
                  helperText:
                      'Trage den abgelesenen Kilometerstand oder die Angabe auf dem Beleg ein.',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                validator: (value) =>
                    (value ?? '').trim().isNotEmpty &&
                        ReadingValue.tryParseWhole(value ?? '') == null
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
              EditableReadingTimeCard(
                value: _capturedAt,
                onPressed: _pickCapturedAt,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Notiz',
                  hintText: 'Optional, z. B. Ölwechsel und neue Bremsbeläge',
                ),
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _working ? null : () => _save(meter),
                icon: _working
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _manual ? Icons.save_outlined : Icons.verified_outlined,
                      ),
                label: Text(
                  _manual
                      ? 'Eintrag speichern'
                      : 'Eintrag bestätigen und speichern',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return PopScope<void>(
      canPop: _allowPop || (!_isEnteringReading && !_working),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: scaffold,
    );
  }

  bool get _isEnteringReading =>
      _manual ||
      _photoEntry ||
      _photoSession.photos.isNotEmpty ||
      _photoSession.documents.isNotEmpty;

  bool get _hasUnsavedChanges =>
      _activity.text.trim().isNotEmpty ||
      _workshop.text.trim().isNotEmpty ||
      _cost.text.trim().isNotEmpty ||
      _photoSession.documents.isNotEmpty ||
      _selectedUnit != null ||
      _photoSession.photos.isNotEmpty ||
      _value.text.trim().isNotEmpty ||
      _note.text.trim().isNotEmpty ||
      _capturedAt != _initialCapturedAt;

  Future<void> _handleBack() async {
    if (_working || _discardDialogOpen) return;
    FocusScope.of(context).unfocus();
    if (!_hasUnsavedChanges) {
      if (_isEnteringReading) {
        await _returnToCaptureOptions();
      } else {
        _leaveForm();
      }
      return;
    }

    _discardDialogOpen = true;
    final discard = await confirmDiscardChanges(
      context,
      title: 'Eintrag verwerfen?',
      message:
          'Dein Fahrzeugeintrag und die ausgewählten Anhänge wurden noch nicht gespeichert.',
      discardLabel: 'Eintrag verwerfen',
    );
    _discardDialogOpen = false;
    if (!mounted || !discard) return;
    await _returnToCaptureOptions();
  }

  Future<void> _returnToCaptureOptions() async {
    setState(() => _saving = true);
    try {
      await _photoSession.discard();
      if (!mounted) return;
      _formKey.currentState?.reset();
      setState(() {
        _manual = false;
        _activity.clear();
        _selectedUnit = null;
        _photoEntry = false;
        _value.clear();
        _note.clear();
        _workshop.clear();
        _cost.clear();
        _initialCapturedAt = DateTime.now();
        _capturedAt = _initialCapturedAt;
      });
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            message:
                'Die ungespeicherten Anhänge konnten nicht entfernt werden. '
                'Bitte versuche es erneut.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _leaveForm() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed('meterDetail', pathParameters: {'id': widget.meterId});
    }
  }

  void _photosChanged() {
    if (_photoSession.documents.isNotEmpty) _photoEntry = true;
    if (mounted) setState(() {});
  }

  Map<String, dynamic> get _draftFields => {
    'value': _value.text,
    'hasMeasurement': _value.text.trim().isNotEmpty,
    'activityText': _activity.text,
    'selectedUnit': _selectedUnit,
    'note': _note.text,
    'workshop': _workshop.text,
    'cost': _cost.text,
    'capturedAt': _capturedAt.toIso8601String(),
    'initialCapturedAt': _initialCapturedAt.toIso8601String(),
    'manual': _manual,
    'photoEntry': _photoEntry,
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

  Future<void> _capture(ReadingSource source, {String? replacementId}) async {
    if (!mounted || _working) return;
    FocusScope.of(context).unfocus();
    final wasEntering = _isEnteringReading;
    try {
      final result = await _photoSession.capture(
        source,
        formFields: _draftFields,
        replacementId: replacementId,
      );
      if (!mounted) return;
      if (result.photos.isNotEmpty) {
        setState(() {
          _photoEntry = true;
          if (!wasEntering) _capturedAt = result.photos.first.capturedAt;
        });
        await _photoSession.rememberFields(_draftFields);
      }
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
              CareActivity.watering.label,
            );
            _selectedUnit = fields['selectedUnit'] as String?;
            _note.text = fields['note'] as String;
            _workshop.text = fields['workshop'] as String? ?? '';
            _cost.text = fields['cost'] as String? ?? '';
            _capturedAt = DateTime.parse(fields['capturedAt'] as String);
            _initialCapturedAt = DateTime.parse(
              fields['initialCapturedAt'] as String,
            );
            _manual = fields['manual'] as bool;
            _photoEntry =
                (fields['photoEntry'] as bool) ||
                _photoSession.photos.isNotEmpty ||
                _photoSession.documents.isNotEmpty;
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

  Future<void> _replacePhoto(ReadingPhotoVersion photo) async {
    final source = await choosePhotoReplacementSource(context);
    if (source != null && mounted) {
      await _capture(source, replacementId: photo.id);
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

  Future<void> _pickCapturedAt() async {
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
    if (time == null) return;
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

  Future<void> _save(Meter meter) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // A long photo list can scroll the form field out of the widget tree.
    if (_activity.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(AppSnackBar(message: 'Bitte eine Aktivität angeben.'));
      return;
    }
    final activity = CareActivitySelection.fromText(_activity.text);
    final hasMeasurement = _value.text.trim().isNotEmpty;
    final value = ReadingValue.tryParseWhole(
      hasMeasurement ? _value.text : '0',
    );
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar(message: 'Bitte eine ganze Zahl ab 0 eingeben.'),
      );
      return;
    }
    final selectedUnit = _selectedUnit ?? meter.unit;
    setState(() => _saving = true);
    try {
      final costCents = parseCostCents(_cost.text);
      var meterForReading = meter;
      if (selectedUnit != meter.unit) {
        meterForReading = meter.copyWith(unit: selectedUnit);
        await ref.read(meterServiceProvider).update(meterForReading);
      }
      final service = ref.read(meterReadingServiceProvider);
      final reading = await service.createWithPhotos(
        readingId: _photoSession.readingId,
        meter: meterForReading,
        activity: activity.activity,
        customActivityLabel: activity.customActivityLabel,
        hasMeasurement: hasMeasurement,
        photos: List.of(_photoSession.photos),
        documents: List.of(_photoSession.documents),
        workshop: _workshop.text,
        costCents: costCents,
        value: value,
        capturedAt: _capturedAt,
        note: _note.text,
      );
      if (selectedUnit != meter.unit) {
        ref.invalidate(meterByIdProvider(meter.id));
      }
      await _photoSession.committed();
      _allowPop = true;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pushReplacementNamed(
        'readingDetail',
        pathParameters: {'id': reading.id},
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!messenger.mounted) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(AppSnackBar(message: 'Fahrzeugeintrag gespeichert.'));
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(message: 'Speichern fehlgeschlagen: $error'),
        );
        setState(() => _saving = false);
      }
    }
  }
}

class _CaptureGuidance extends StatelessWidget {
  const _CaptureGuidance();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Veränderungen festhalten',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text('• Fahrzeug oder Beleg gut lesbar fotografieren'),
            const Text('• Spiegelungen und Schatten vermeiden'),
            const Text('• Für Vergleiche einen ähnlichen Blickwinkel wählen'),
            const SizedBox(height: 10),
            Text(
              'Das Fahrzeugfoto wird für die lokale Speicherung auf maximal 1920 Pixel an der längsten Kante verkleinert und als JPEG optimiert. Aufnahme- und Standortmetadaten werden nicht übernommen. Den Kilometerstand kannst du optional selbst eintragen.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
