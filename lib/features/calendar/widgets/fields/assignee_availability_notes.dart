import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// One "why this person can't take the job" line.
///
/// [figure] is the mono right-hand column: a date range for a day off (which
/// has no clock, so rendering `00:00–23:59` would be noise dressed as
/// precision) and the daily window for a booked job, which is the actionable
/// half — it shows that starting at noon would free them.
class AssigneeNote {
  const AssigneeNote({required this.sentence, required this.figure});

  final String sentence;
  final String figure;
}

/// The lines under the assignee chips saying who can't take the job and why.
///
/// **Two, then a count.** One line per clash buries Save on a holiday Monday,
/// so the rest collapse behind "{count} more aren't free", which expands in
/// place.
class AssigneeAvailabilityNotes extends StatefulWidget {
  const AssigneeAvailabilityNotes({required this.notes, super.key});

  /// How many lines show before the rest collapse behind the count.
  static const int collapseAfter = 2;

  final List<AssigneeNote> notes;

  @override
  State<AssigneeAvailabilityNotes> createState() =>
      _AssigneeAvailabilityNotesState();
}

class _AssigneeAvailabilityNotesState extends State<AssigneeAvailabilityNotes> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    final hidden = _expanded
        ? 0
        : notes.length - AssigneeAvailabilityNotes.collapseAfter;
    final shown = hidden > 0
        ? notes.take(AssigneeAvailabilityNotes.collapseAfter)
        : notes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final note in shown) _NoteRow(note: note),
        if (hidden > 0)
          _MoreRow(
            count: hidden,
            onTap: () => setState(() => _expanded = true),
          ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note});

  final AssigneeNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sp4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              note.sentence,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sp8),
          Text(note.figure, style: theme.monoType.data),
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sp4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp4),
          child: Text(
            context.l10n.calendar_assigneesMoreNotFree(count),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.palette.primaryAccent,
            ),
          ),
        ),
      ),
    );
  }
}
