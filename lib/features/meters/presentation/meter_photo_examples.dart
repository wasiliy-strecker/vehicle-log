import 'package:flutter/material.dart';

const meterPhotoExamples = [
  (
    label: 'Ganzes Fahrzeug',
    icon: Icons.directions_car_outlined,
    description:
        'Fotografiere das Fahrzeug vollständig. Ein ruhiger Hintergrund macht Veränderungen gut sichtbar.',
  ),
  (
    label: 'Schäden und Reparaturen',
    icon: Icons.car_repair_outlined,
    description:
        'Halte Schäden und ausgeführte Arbeiten als Nahaufnahme fest. Ergänze die Details in der Notiz.',
  ),
  (
    label: 'Werkstattunterlagen',
    icon: Icons.document_scanner_outlined,
    description:
        'Scanne Rechnungen und Prüfberichte über „PDF auswählen/scannen“ oder fotografiere einzelne Belege.',
  ),
  (
    label: 'Kilometerstand vergleichen',
    icon: Icons.speed_outlined,
    description:
        'Fotografiere den abgelesenen Tachostand. Den Kilometerstand trägst du selbst in das Formular ein.',
  ),
];

class MeterPhotoExamplesButton extends StatelessWidget {
  const MeterPhotoExamplesButton({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.center,
    child: TextButton.icon(
      icon: const Icon(Icons.collections_outlined),
      label: const Text('Fotohinweise', textAlign: TextAlign.center),
      onPressed: !enabled
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              useSafeArea: true,
              isScrollControlled: true,
              builder: (context) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: .7,
                maxChildSize: .95,
                builder: (context, controller) => ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Fahrzeuge fotografieren',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Schließen',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    for (final example in meterPhotoExamples)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                example.icon,
                                color: Theme.of(context).colorScheme.primary,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                example.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(example.description),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    ),
  );
}
