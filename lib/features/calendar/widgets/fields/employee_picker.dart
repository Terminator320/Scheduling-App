import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/assignee_availability.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/fields/assignee_availability_notes.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/warning_note.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

class EmployeePicker extends StatelessWidget {
  const EmployeePicker({
    required this.allEmployees,
    required this.selectedEmployees,
    super.key,
    this.selectable = true,
    this.hasError = false,
    this.errorText,
    this.onToggle,
    this.availability = AssigneeAvailability.none,
  });

  final List<EmployeeRecord> allEmployees;
  final List<EmployeeRecord> selectedEmployees;
  final bool selectable;
  final bool hasError;

  /// When this is non-null, an error row is rendered below the chips and their borders get highlighted.
  final String? errorText;
  final void Function(EmployeeRecord)? onToggle;

  /// Who can't take the job on the chosen date, and why. Empty until a date is
  /// picked and the lookup settles — no dimming and no divider until then, so
  /// an unanswered question never reads as "everyone is free".
  final AssigneeAvailability availability;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = this.hasError || errorText != null;
    // In read-only mode the picker is a summary of who is ON the job, so the
    // unselected staff are not rendered at all.
    final displayEmployees = selectable
        ? allEmployees
        : allEmployees
              .where((e) => selectedEmployees.any((s) => s.id == e.id))
              .toList();

    // Hoisted, not rebuilt per chip: both inputs are the same for every
    // employee, and `among` re-scans the roster, so inlining them made the
    // naming pass quadratic on a widget that rebuilds on every form keystroke.
    final selectedIds = {for (final e in selectedEmployees) e.id};
    final clashingIds = availability.clashes.keys.toSet();
    // A TALLY, not the raw names: `shortAssigneeName` runs once per chip, and
    // handing it the list made it re-split every candidate for every employee.
    final names = firstNameTally([for (final e in displayEmployees) e.name]);
    final offers = [
      for (final employee in displayEmployees)
        (
          employee: employee,
          state: assigneeOfferState(
            employeeId: employee.id,
            clashingIds: clashingIds,
            selectedIds: selectedIds,
            alreadyAssignedIds: availability.alreadyAssignedIds,
          ),
          shortName: shortAssigneeName(employee.name, among: names),
        ),
    ];

    final content = displayEmployees.isEmpty
        ? Text(
            selectable
                ? context.l10n.common_noEmployeesFound
                : context.l10n.calendar_noEmployeesAssigned,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          )
        : Wrap(
            spacing: AppSpacing.sp8,
            runSpacing: AppSpacing.sp8,
            children: [
              for (final offer in offers)
                _EmployeeChip(
                  employee: offer.employee,
                  shortName: offer.shortName,
                  isSelected: selectedIds.contains(offer.employee.id),
                  isUnavailable: offer.state == AssigneeOfferState.unavailable,
                  hasError: hasError,
                  // An unavailable chip is not tappable — dimming means "can't
                  // pick this", and there is no glyph doing that work for it.
                  onTap:
                      selectable &&
                          offer.state != AssigneeOfferState.unavailable
                      ? () => onToggle?.call(offer.employee)
                      : null,
                ),
            ],
          );

    final availabilityBlock = selectable
        ? _availabilityBlock(context, offers)
        : null;

    if (errorText == null && availabilityBlock == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        content,
        ?availabilityBlock,
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sp4,
              left: AppSpacing.sp4,
            ),
            child: Text(
              errorText!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }

  /// The divider plus either the per-person lines or, when there is nobody
  /// left to pick, the one amber sentence that replaces them.
  ///
  /// Null when nothing clashes — no date picked yet, or everyone is free.
  Widget? _availabilityBlock(BuildContext context, List<_Offer> offers) {
    final notes = [
      for (final offer in offers)
        if (availability.clashes[offer.employee.id] case final clash?)
          _noteFor(
            context,
            name: offer.shortName,
            clash: clash,
            onTheJob: offer.state == AssigneeOfferState.onTheJob,
          ),
    ];
    if (notes.isEmpty) return null;

    // "Nobody free" is every OFFERED assignee dimmed — someone kept on the job
    // despite a clash still leaves a crew here, so the per-person lines are
    // still the more useful thing to say.
    final nobodyFree = offers.every(
      (o) => o.state == AssigneeOfferState.unavailable,
    );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sp12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          if (nobodyFree)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sp8),
              child: WarningNote(
                message: context.l10n.calendar_nobodyFreeThen(
                  availability.whenLabel,
                ),
                filled: false,
              ),
            )
          else
            AssigneeAvailabilityNotes(notes: notes),
        ],
      ),
    );
  }

  AssigneeNote _noteFor(
    BuildContext context, {
    required String name,
    required AppointmentRecord clash,
    required bool onTheJob,
  }) {
    final l10n = context.l10n;
    // Four sentences, not three: someone ALREADY on the job who also has
    // another booking must not read as a refusal. That is the ordinary
    // outcome of moving the date after picking the crew, and their chip is
    // still selected and still tappable.
    return AssigneeNote(
      sentence: switch ((clash.isTimeOff, onTheJob)) {
        (true, true) => l10n.calendar_assigneeOffStillOnJob(name),
        (true, false) => l10n.calendar_dayOffIsOff(name),
        (false, true) => l10n.calendar_assigneeBookedStillOnJob(name),
        (false, false) => l10n.calendar_assigneeOnAnotherJob(name),
      },
      figure: clash.isTimeOff
          ? DateUtilsHelper.formatDayRange(
              clash.startTime,
              lastWorkDayOf(clash),
            )
          : '${DateUtilsHelper.formatTime(clash.startTime)} – '
                '${DateUtilsHelper.formatTime(clash.endTime)}',
    );
  }
}

/// One offered assignee, with everything the chip and its line both need
/// resolved once per build rather than per widget.
typedef _Offer = ({
  EmployeeRecord employee,
  AssigneeOfferState state,
  String shortName,
});

/// One staff chip. Its own widget so a row rebuilds on its own rather than as
/// part of a 60-line closure body re-evaluated per employee.
class _EmployeeChip extends StatelessWidget {
  const _EmployeeChip({
    required this.employee,
    required this.shortName,
    required this.isSelected,
    required this.isUnavailable,
    required this.hasError,
    required this.onTap,
  });

  final EmployeeRecord employee;
  final String shortName;
  final bool isSelected;

  /// Dimmed and untappable: a dashed empty slot rather than a button. One
  /// treatment for every reason — the line underneath says which.
  final bool isUnavailable;
  final bool hasError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      // Non-null onTap IS selectable — the two cannot disagree.
      button: onTap != null,
      selected: isSelected,
      enabled: !isUnavailable,
      label: employee.name,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sp8,
            AppSpacing.sp4,
            AppSpacing.sp12,
            AppSpacing.sp4,
          ),
          foregroundDecoration: isUnavailable
              ? _DashedPill(color: scheme.outlineVariant)
              : null,
          decoration: BoxDecoration(
            color: isUnavailable
                ? Colors.transparent
                : isSelected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            border: isUnavailable
                ? null
                : Border.all(
                    // An unselected chip carries the error outline, since "pick
                    // someone" is what the error is asking for.
                    color: hasError && !isSelected
                        ? scheme.error
                        : isSelected
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: 1.5,
                  ),
            borderRadius: BorderRadius.circular(AppRadius.rFull),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: isUnavailable ? 0.42 : 1,
                child: AppAvatar(
                  name: employee.name,
                  color: employee.color,
                  size: AvatarSize.xs,
                ),
              ),
              const SizedBox(width: AppSpacing.sp8),
              Flexible(
                child: Text(
                  shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isUnavailable
                        ? theme.palette.textTertiary
                        : isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
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

/// The unavailable chip's dashed outline.
///
/// A `Border` cannot dash, and the dash is what makes the chip read as an empty
/// SLOT rather than a faint button — the one non-colour cue that it can't be
/// picked, since the design dropped the per-chip glyphs.
class _DashedPill extends Decoration {
  const _DashedPill({required this.color});

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedPillPainter(color);
}

class _DashedPillPainter extends BoxPainter {
  _DashedPillPainter(this.color);

  static const double _dash = 4;
  static const double _gap = 3;

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = offset & size;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(0.75),
          Radius.circular(size.height / 2),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance = next + _gap;
      }
    }
  }
}
