import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/widgets/fields/repeat_interval_picker.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_widgets.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

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
          customValue: PhotoPickerSection(
            existingImages: existingImages,
            newImages: newImages,
            isEditing: false,
            onPickImages: () {},
            onRemoveExisting: (_) {},
            onRemoveNew: (_) {},
            failedCount: failedCount,
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
      ],
    );
  }
}
