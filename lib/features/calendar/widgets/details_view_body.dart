import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/client_contacts_section.dart';
import 'package:scheduling/features/calendar/widgets/details_action_bar.dart';
import 'package:scheduling/features/calendar/widgets/details_view_widgets.dart';
import 'package:scheduling/features/calendar/widgets/photo_picker_section.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';

/// Read-only body of `EventDetailsSheet`. Reads everything from the
/// controller; dispatches edit/mark-as-done/cancel actions back through it.
///
/// `onClose` is wired by the shell to `Navigator.pop` so the body never
/// touches the navigator directly.
class DetailsViewBody extends ConsumerWidget {
  const DetailsViewBody({
    required this.appointment,
    required this.showActions,
    required this.onClose,
    super.key,
  });

  final AppointmentRecord appointment;
  final bool showActions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow the watch to the fields this body reads directly. Child widgets
    // (_EmployeesView, _PhotosView, ClientContactsSection) watch their own
    // slices below — passing full `state` down would resurrect the broad watch.
    final provider = eventDetailsControllerProvider(appointment);
    final client = ref.watch(provider.select((s) => s.client));
    final isSaving = ref.watch(provider.select((s) => s.isSaving));
    final notifier = ref.read(provider.notifier);

    final isCancelled = appointment.status.toLowerCase() == 'cancelled';
    final isDone =
        appointment.status.toLowerCase() == 'done' ||
        appointment.status.toLowerCase() == 'completed';
    final now = DateTime.now();
    final isToday =
        appointment.startTime.year == now.year &&
        appointment.startTime.month == now.month &&
        appointment.startTime.day == now.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showActions && !isCancelled)
          Align(
            alignment: Alignment.centerRight,
            child: _EditChip(onTap: notifier.enterEditing),
          ),
        _Header(appointment: appointment),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        DetailsSectionRow(
          label: context.l10n.client,
          value: client?.displayName ?? appointment.clientName,
          subtitle: appointment.clientPhone.isNotEmpty
              ? appointment.clientPhone
              : context.l10n.noNumber,
        ),
        if ((client?.contacts ?? const <ClientContact>[]).isNotEmpty)
          ClientContactsSection(contacts: client!.contacts),
        const SizedBox(height: AppSpacing.sp16),
        DetailsAddressRow(
          label: context.l10n.address,
          address: appointment.address.isNotEmpty
              ? AddressParser.canonicalToDisplay(appointment.address)
              : context.l10n.noAddress,
          onTap: appointment.address.isNotEmpty
              ? () => AddressMapLauncher.showMapChoices(
                  context,
                  address: appointment.address,
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sp16),
        DetailsSectionRow(
          label: context.l10n.notes,
          value: appointment.notes.isNotEmpty
              ? appointment.notes
              : context.l10n.noNotes,
        ),
        const SizedBox(height: AppSpacing.sp16),
        _MaterialsRow(materials: appointment.materialsNeeded),
        const SizedBox(height: AppSpacing.sp16),
        _EmployeesView(appointment: appointment),
        const SizedBox(height: AppSpacing.sp16),
        _PhotosView(
          appointment: appointment,
          isCancelled: isCancelled,
          onRetry: notifier.enterEditing,
        ),
        DetailsActionBar(
          isToday: isToday,
          isDone: isDone,
          isCancelled: isCancelled,
          isSaving: isSaving,
          showCancel: showActions,
          onMarkDone: () async {
            if (await notifier.markAsDone(appointment)) {
              if (!context.mounted) return;
              ref
                  .read(noticeServiceProvider)
                  .success(context.l10n.appointmentMarkedAsDone);
              onClose();
            }
          },
          onCancel: () async {
            if (await notifier.cancelAppointment(appointment)) {
              if (!context.mounted) return;
              ref
                  .read(noticeServiceProvider)
                  .success(context.l10n.appointmentCancelled);
              onClose();
            }
          },
        ),
        if (showActions) ...[
          // TODO(pre-ship): Remove the SizedBox and OutlinedButton below — testing only.
          const SizedBox(height: AppSpacing.sp8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: isSaving
                ? null
                : () async {
                    final confirmed = await _confirmDeleteDialog(context);
                    if (!context.mounted || !confirmed) return;
                    if (await notifier.deleteAppointment(appointment)) {
                      if (!context.mounted) return;
                      ref
                          .read(noticeServiceProvider)
                          .success(context.l10n.appointmentDeleted);
                      onClose();
                    }
                  },
            icon: const Icon(Icons.delete_outline, size: 15),
            label: Text(context.l10n.deleteAppointment),
          ),
        ],
      ],
    );
  }
}

class _EditChip extends StatelessWidget {
  const _EditChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          border: Border.all(color: scheme.outlineVariant, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.r8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, size: 13, color: scheme.onSurface),
            const SizedBox(width: 5),
            Text(
              context.l10n.edit,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.appointment});

  final AppointmentRecord appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
      child: Column(
        children: [
          Text(
            appointment.title,
            style: theme.textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sp8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 4,
            children: [
              _IconLabel(
                icon: Icons.calendar_today_outlined,
                text: DateUtilsHelper.formatDate(appointment.startTime),
                scheme: scheme,
                theme: theme,
              ),
              _IconLabel(
                icon: Icons.access_time_outlined,
                text:
                    '${DateUtilsHelper.formatTime(appointment.startTime)}'
                    ' – ${DateUtilsHelper.formatTime(appointment.endTime)}',
                scheme: scheme,
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconLabel extends StatelessWidget {
  const _IconLabel({
    required this.icon,
    required this.text,
    required this.scheme,
    required this.theme,
  });

  final IconData icon;
  final String text;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MaterialsRow extends StatelessWidget {
  const _MaterialsRow({required this.materials});

  final String materials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DetailsSectionRow(
      label: context.l10n.materialsNeeded,
      value: materials.isEmpty ? context.l10n.noMaterials : '',
      customValue: materials.isNotEmpty
          ? Wrap(
              spacing: 6,
              runSpacing: 6,
              children: materials
                  .split(',')
                  .map((m) => m.trim())
                  .where((m) => m.isNotEmpty)
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
            )
          : null,
    );
  }
}

class _EmployeesView extends ConsumerWidget {
  const _EmployeesView({required this.appointment});

  final AppointmentRecord appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedEmployees = ref.watch(
      eventDetailsControllerProvider(
        appointment,
      ).select((s) => s.selectedEmployees),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.employees.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        if (selectedEmployees.isEmpty)
          Text(
            context.l10n.noEmployeesAssigned,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          ...selectedEmployees.map((e) => DetailsEmployeePill(employee: e)),
      ],
    );
  }
}

class _PhotosView extends ConsumerWidget {
  const _PhotosView({
    required this.appointment,
    required this.isCancelled,
    required this.onRetry,
  });

  final AppointmentRecord appointment;
  final bool isCancelled;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = eventDetailsControllerProvider(appointment);
    final existingImages = ref.watch(provider.select((s) => s.existingImages));
    final newImages = ref.watch(provider.select((s) => s.newImages));
    final notifier = ref.watch(photoUploadNotifierProvider);
    final appointmentId = appointment.id;
    final failure = appointmentId != null
        ? notifier.failureFor(appointmentId)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.pictures.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: AppSpacing.sp8),
        PhotoPickerSection(
          existingImages: existingImages,
          newImages: newImages,
          isEditing: false,
          onPickImages: () {},
          onRemoveExisting: (_) {},
          onRemoveNew: (_) {},
          failedCount: failure?.failedCount ?? 0,
          tooLargeFileNames: failure?.tooLargeFileNames ?? const [],
          onRetry: (failure?.failedCount ?? 0) > 0 && !isCancelled
              ? () {
                  if (appointmentId != null) {
                    notifier.clearFailure(appointmentId);
                  }
                  onRetry();
                }
              : null,
        ),
      ],
    );
  }
}

// TODO(pre-ship): Remove this entire function — used only by the testing delete button above.
Future<bool> _confirmDeleteDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.deleteAppointment),
      content: Text(ctx.l10n.areYouSureYouWantToDeleteThisJob),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.l10n.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}
