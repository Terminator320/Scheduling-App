import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The divider between the month grid and the day's jobs, doubling as the
/// grab handle that collapses the grid. Painted as the same hairline the rest
/// of the screen uses, inside a 20px tall target with a short grip so it reads
/// as draggable; it is also a button, since a 24px drag is not a gesture
/// everyone can make.
class CollapseHandle extends StatelessWidget {
  const CollapseHandle({
    required this.isCollapsed,
    required this.onDrag,
    required this.onDragEnd,
    required this.onToggle,
    super.key,
  });

  final bool isCollapsed;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isCollapsed
        ? context.l10n.calendar_showCalendar
        : context.l10n.calendar_hideCalendar;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
          onVerticalDragEnd: (_) => onDragEnd(),
          onVerticalDragCancel: onDragEnd,
          onTap: onToggle,
          child: SizedBox(
            height: 20,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.palette.textFaint,
                    borderRadius: BorderRadius.circular(AppRadius.rFull),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
