import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../domain/meter_reading.dart';

class CareActivityField extends ConsumerStatefulWidget {
  const CareActivityField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool autofocus;

  @override
  ConsumerState<CareActivityField> createState() => _CareActivityFieldState();
}

class _CareActivityFieldState extends ConsumerState<CareActivityField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<Iterable<String>> _loadOptions(TextEditingValue value) {
    final result = Completer<Iterable<String>>();
    Future<void> deliver() async {
      List<String> suggestions;
      try {
        suggestions = await ref.read(careActivitySuggestionsProvider.future);
      } on Object {
        suggestions = careActivitySuggestions(const []);
      }
      // Cancel delivery when this field is disposed. Completing even with an
      // empty list would let RawAutocomplete update its already disposed overlay.
      if (!mounted) return;
      final query = value.text.trim().toLowerCase();
      result.complete(
        widget.enabled
            ? suggestions.where((label) => label.toLowerCase().contains(query))
            : const Iterable<String>.empty(),
      );
    }

    unawaited(deliver());
    return result.future;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(careActivitySuggestionsProvider);
    return Autocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsMaxHeight: 220,
      optionsBuilder: _loadOptions,
      onSelected: (value) {
        widget.onChanged(value);
        _focus.unfocus();
      },
      fieldViewBuilder: (context, controller, focusNode, _) => TextFormField(
        key: const ValueKey('care-activity'),
        controller: controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        decoration: const InputDecoration(
          labelText: 'Aktivität',
          hintText: 'z. B. Wartung oder Erste Blüte',
          helperText: 'Vorschlag auswählen oder eigene Aktivität eingeben.',
          helperMaxLines: 2,
        ),
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: widget.onChanged,
        onFieldSubmitted: (_) => focusNode.unfocus(),
        onTapOutside: (_) => focusNode.unfocus(),
        validator: (value) => (value ?? '').trim().isEmpty
            ? 'Bitte eine Aktivität angeben.'
            : null,
      ),
    );
  }
}

String activityTextFromDraft(Map<String, dynamic> fields, String fallback) {
  if (fields.containsKey('activityText')) {
    return fields['activityText'] as String;
  }
  final legacy = fields['activity'] as String?;
  if (legacy == null) return fallback;
  final activity = CareActivity.values.byName(legacy);
  return activity == CareActivity.custom
      ? fields['customActivityLabel'] as String? ?? fallback
      : activity.label;
}
