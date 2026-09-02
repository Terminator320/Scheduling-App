import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/widgets/fields/repeat_interval_picker.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_widgets.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/feedback/warning_note.dart';

class DetailsEditChip extends StatelessWidget {
  const DetailsEditChip({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r8),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sp12,
            vertical: AppSpacing.sp4,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: scheme.outlineVariant, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.r8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, size: 13, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sp4),
              Text(
                context.l10n.common_edit,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailsHeader extends StatelessWidget {
  const DetailsHeader({
    required this.appointment,
    required this.status,
    required this.compact,
    super.key,
  });

  final AppointmentRecord appointment;
  final AppointmentStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
      appointment.title,
      style: theme.textTheme.headlineLarge,
    );
    final chip = StatusChip(status: status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) ...[
            title,
            const SizedBox(height: AppSpacing.sp8),
            chip,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: AppSpacing.sp12),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sp4),
                  child: chip,
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.sp8),
          // One mono line replaces the old calendar/clock icon rows.
          Text(
            DateUtilsHelper.formatWhenLine(
              appointment.startTime,
              appointment.endTime,
              allDayLabel: appointment.isAllDay
                  ? context.l10n.calendar_allDay
                  : null,
              // The sheet is not day-scoped, so it names the whole run rather
              // than a "Day N of M" counter — otherwise a 5-day job opened
              // from its day 3 card still read as day 1 with no hint it ran on.
              lastDay: lastWorkDayOf(appointment),
            ),
            style: theme.monoType.data,
          ),
          if (appointment.repeat != RepeatInterval.none) ...[
            const SizedBox(height: AppSpacing.sp4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.repeat,
                  size: 13,
                  color: theme.palette.textTertiary,
                ),
                const SizedBox(width: AppSpacing.sp4),
                Flexible(
                  child: Text(
                    repeatIntervalLabel(context.l10n, appointment.repeat),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.palette.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Started 9:12 AM · Finished 11:40 AM · 2 h 28 min" — the job's time
/// record, one mono line under the header. Either half may be absent (a job
/// under way has no finish; a job closed from the edit form was never
/// started), and the elapsed segment needs both.
class DetailsTimeRecordRow extends StatelessWidget {
  const DetailsTimeRecordRow({
    required this.startedAt,
    required this.completedAt,
    super.key,
  });

  final DateTime? startedAt;
  final DateTime? completedAt;

  /// The segments, joined by the same middot the when-line uses.
  static String label(
    AppLocalizations l10n,
    DateTime? started,
    DateTime? done,
  ) {
    final parts = <String>[
      if (started != null)
        l10n.calendar_timeRecordStarted(DateUtilsHelper.formatTime(started)),
      if (done != null)
        l10n.calendar_timeRecordFinished(DateUtilsHelper.formatTime(done)),
      if (started != null && done != null && done.isAfter(started))
        elapsedLabel(l10n, done.difference(started)),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.sp4,
        right: AppSpacing.sp4,
        top: AppSpacing.sp4,
      ),
      child: Text(
        label(context.l10n, startedAt, completedAt),
        style: theme.monoType.data.copyWith(color: theme.palette.textTertiary),
      ),
    );
  }
}

/// "2 h 28 min" / "45 min".
String elapsedLabel(AppLocalizations l10n, Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes % 60;
  return hours > 0
      ? l10n.calendar_elapsedHoursMinutes(hours, minutes)
      : l10n.calendar_elapsedMinutes(minutes);
}

/// "Marc is running late · 9:12 AM" — what an assignee last signalled on the
/// way to this job, for whoever opens it. Unfilled: it sits inside the
/// sheet's own surface, where a second amber panel reads as a nested box.
class DetailsCrewSignalLine extends StatelessWidget {
  const DetailsCrewSignalLine({required this.appointment, super.key});

  final AppointmentRecord appointment;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final at = appointment.crewStatusAt;
    final time = at == null ? '' : DateUtilsHelper.formatTime(at);
    final name =
        assigneeNameAt(
          appointment.employeeNames,
          appointment.employeeIds.indexOf(appointment.crewStatusBy),
        ) ??
        l10n.calendar_crewFallbackName;
    final isLate = appointment.crewStatus == 'runningLate';
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.sp4,
        right: AppSpacing.sp4,
        top: AppSpacing.sp8,
      ),
      child: WarningNote(
        filled: false,
        icon: isLate ? Icons.schedule_rounded : Icons.directions_car_outlined,
        message: isLate
            ? l10n.calendar_crewRunningLateAt(name, time)
            : l10n.calendar_crewOnMyWayAt(name, time),
      ),
    );
  }
}

class DetailsMaterialsRow extends StatelessWidget {
  const DetailsMaterialsRow({required this.items, super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DetailsSectionRow(
      label: context.l10n.calendar_materialsNeeded,
      value: '',
      customValue: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: items
            .map(
              (m) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(AppRadius.rFull),
                ),
                child: Text(
                  m,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class DetailsEmployeesView extends ConsumerWidget {
  const DetailsEmployeesView({required this.appointment, super.key});

  final AppointmentRecord appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedEmployees = ref.watch(
      eventDetailsControllerProvider(
        EventDetailsKey(appointment),
      ).select((s) => s.selectedEmployees),
    );
    if (selectedEmployees.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp16),
        DetailsSectionRow(
          label: context.l10n.calendar_assignedLabel,
          value: '',
          customValue: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in selectedEmployees)
                DetailsEmployeePill(employee: e),
            ],
          ),
        ),
      ],
    );
  }
}

class DetailsPhotosView extends ConsumerWidget {
  const DetailsPhotosView({
    required this.appointment,
    required this.isCancelled,
    required this.onRetry,
    super.key,
  });

  final AppointmentRecord appointment;
  final bool isCancelled;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    final existingImages = ref.watch(provider.select((s) => s.existingImages));
    final newImages = ref.watch(provider.select((s) => s.newImages));
    final notifier = ref.watch(photoUploadNotifierProvider);
    final appointmentId = appointment.id;
    final failure = appointmentId != null
        ? notifier.failureFor(appointmentId)
        : null;
    final failedCount = failure?.failedCount ?? 0;
    final hasPhotos =
        existingImages.isNotEmpty || newImages.isNotEmpty || failedCount > 0;
    if (!hasPhotos) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp16),
        DetailsSectionRow(
          label: context.l10n.calendar_photosLabel,
          value: '',
          // The queue depth is a ValueNotifier rather than a provider, so the
          // rebuild is scoped to this row: a drain of a long queue republishes
          // per entry, and rebuilding the whole detail body each time would be
          // a real cost on the screen a technician has open in the field.
          customValue: ValueListenableBuilder<Map<String, int>>(
            valueListenable: notifier.pending,
            builder: (context, pending, _) => PhotoPickerSection(
              existingImages: existingImages,
              newImages: newImages,
              isEditing: false,
              onPickImages: () {},
              onRemoveExisting: (_) {},
              onRemoveNew: (_) {},
              failedCount: failedCount,
              pendingCount: appointmentId == null
                  ? 0
                  : pending[appointmentId] ?? 0,
              tooLargeFileNames: failure?.tooLargeFileNames ?? const [],
              onRetry: failedCount > 0 && !isCancelled
                  ? () {
                      if (appointmentId != null) {
                        notifier.clearFailure(appointmentId);
                      }
                      onRetry();
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
