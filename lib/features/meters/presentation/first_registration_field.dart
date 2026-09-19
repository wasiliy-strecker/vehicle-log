import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

DateTime? _registrationDate(String value) {
  // Keep existing month/year values readable without inventing a stored day.
  final match = RegExp(
    r'^(?:(\d{2})\.)?(\d{2})\.([12]\d{3})$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final day = int.parse(match[1] ?? '1');
  final month = int.parse(match[2]!);
  final year = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

String? firstRegistrationError(String? value) =>
    (value ?? '').trim().isEmpty || _registrationDate(value!) != null
    ? null
    : 'Bitte ein gültiges Datum auswählen.';

class FirstRegistrationField extends StatelessWidget {
  const FirstRegistrationField({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool enabled;

  Future<void> _pickDate(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final firstDate = DateTime(1800);
    final lastDate = DateUtils.dateOnly(DateTime.now());
    final existing = _registrationDate(controller.text) ?? lastDate;
    final initialDate = existing.isBefore(firstDate)
        ? firstDate
        : existing.isAfter(lastDate)
        ? lastDate
        : existing;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDatePickerMode: DatePickerMode.year,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Erstzulassung wählen',
      confirmText: 'Übernehmen',
      cancelText: 'Abbrechen',
    );
    if (selected != null && context.mounted) {
      controller.text = formatDate(selected);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextFormField(
          controller: controller,
          enabled: enabled,
          readOnly: true,
          showCursor: false,
          onTap: enabled ? () => _pickDate(context) : null,
          decoration: InputDecoration(
            labelText: 'Erstzulassung (optional)',
            hintText: 'Datum auswählen',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Erstzulassung entfernen',
                    onPressed: enabled ? controller.clear : null,
                    icon: const Icon(Icons.clear),
                  ),
                IconButton(
                  tooltip: 'Erstzulassung auswählen',
                  onPressed: enabled ? () => _pickDate(context) : null,
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ],
            ),
          ),
          validator: firstRegistrationError,
        ),
      );
}
