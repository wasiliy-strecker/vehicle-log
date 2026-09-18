import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Full-width stacked actions when two columns would become hard to read.
class AppActionRow extends StatelessWidget {
  const AppActionRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 320 ||
          MediaQuery.textScalerOf(context).scale(16) >= 24;
      if (stacked) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              children[index],
            ],
          ],
        );
      }
      return Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 12),
            Expanded(child: children[index]),
          ],
        ],
      );
    },
  );
}

/// An extended FAB whose label can wrap without exceeding the screen width.
class AppFloatingActionButton extends StatelessWidget {
  const AppFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  static double _labelWidth(BuildContext context) => math.max(
    1,
    MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal -
        32 -
        AppTheme.actionPadding.horizontal -
        AppTheme.actionIconSize -
        8,
  );

  /// Scrollable content must be able to move clear of a multiline FAB.
  static double contentBottomPadding(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: AppTheme.actionTextStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: _labelWidth(context));
    final height = painter.height + AppTheme.actionPadding.vertical;
    painter.dispose();
    return math.max(112, height + 32);
  }

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    onPressed: onPressed,
    icon: Icon(icon, size: AppTheme.actionIconSize),
    label: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _labelWidth(context)),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}
