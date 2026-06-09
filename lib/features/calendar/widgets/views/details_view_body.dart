import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/delete_appointment_dialog.dart';
import 'package:scheduling/features/calendar/widgets/fields/repeat_interval_picker.dart';
import 'package:scheduling/features/calendar/widgets/sections/client_contacts_section.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/views/details_action_bar.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_widgets.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/info_card.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/quick_action_button.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

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
    final provider = eventDetailsControllerProvider(appointment);
    final client = ref.watch(provider.select((s) => s.client));
    final isSaving = ref.watch(provider.select((s) => s.isSaving));
    final notifier = ref.read(provider.notifier);

    final status = AppointmentStatus.fromRaw(appointment.status);
    final isCancelled = status.isCancelled;
    final isDone = status.isDone;
    final now = DateTime.now();
    final isToday =
        appointment.startTime.year == now.year &&
        appointment.startTime.month == now.month &&
        appointment.startTime.day == now.day;

    // Call / Directions handlers are built here (where `ref` lives); the phone
    // and address themselves move into these quick actions rather than rows.
    final clientName = client?.displayName ?? appointment.clientName;
    final phone = (client?.phone.isNotEmpty ?? false)
        ? client!.phone
        : appointment.clientPhone;
    final onCall = phone.isNotEmpty
        ? () => launchPhoneCall(context, ref, phone)
        : null;
    final onDirections = appointment.address.isNotEmpty
        ? () => AddressMapLauncher.showMapChoices(
            context,
            address: appointment.address,
          )
        : null;

    final notes = appointment.notes;
    final materials = appointment.materialsNeeded
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    // contacts[0] mirrors the primary client already named above — only the
    // remaining business contacts are worth listing again.
    final extraContacts = (client?.contacts ?? const <ClientContact>[])
        .skip(1)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showActions && !isCancelled)
          Align(
            alignment: Alignment.centerRight,
            child: _EditChip(onTap: notifier.enterEditing),
          ),
        _Header(appointment: appointment, status: status),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        if (onCall != null || onDirections != null) ...[
          QuickActionsRow(
            buttons: [
              if (onCall != null)
                QuickActionButton(
                  icon: Icons.phone_outlined,
                  label: context.l10n.clients_call,
                  onTap: onCall,
                ),
              if (onDirections != null)
                QuickActionButton(
                  icon: Icons.directions_outlined,
                  label: context.l10n.clients_directions,
                  onTap: onDirections,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sp24),
        ],
        SectionLabel(context.l10n.calendar_client),
        const SizedBox(height: AppSpacing.sp8),
        InfoCard(
          rows: [InfoCardRow(icon: Icons.person_outline, text: clientName)],
        ),
        if (extraContacts.isNotEmpty)
          ClientContactsSection(contacts: extraContacts),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sp16),
          DetailsSectionRow(label: context.l10n.calendar_notes, value: notes),
        ],
        if (materials.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sp16),
          _MaterialsRow(items: materials),
        ],
        _EmployeesView(appointment: appointment),
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
                  .success(context.l10n.common_appointmentMarkedAsDone);
              onClose();
            }
          },
          onCancel: () async {
            if (await notifier.cancelAppointment(appointment)) {
              if (!context.mounted) return;
              ref
                  .read(noticeServiceProvider)
                  .success(context.l10n.common_appointmentCancelled);
              onClose();
            }
          },
        ),
        if (showActions)
          _DeleteTestButton(
            appointment: appointment,
            isSaving: isSaving,
            notifier: notifier,
            onClose: onClose,
          ),
      ],
    );
  }
}

// TODO(pre-ship): Remove this entire widget — testing-only delete control.
class _DeleteTestButton extends ConsumerWidget {
  const _DeleteTestButton({
    required this.appointment,
    required this.isSaving,
    required this.notifier,
    required this.onClose,
  });

  final AppointmentRecord appointment;
  final bool isSaving;
  final EventDetailsController notifier;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp8),
        OutlinedButton.icon(
          style: destructiveOutlinedButtonStyle(
            context,
            minimumSize: const Size(double.infinity, 44),
          ),
          onPressed: isSaving
              ? null
              : () async {
                  final choice = await showDeleteAppointmentDialog(
                    context,
                    isSeries: appointment.seriesId.isNotEmpty,
                  );
                  if (!context.mounted || choice == null) return;
                  final error = await notifier.deleteAppointment(
                    appointment,
                    includeFuture:
                        choice == DeleteAppointmentChoice.thisAndFuture,
                  );
                  if (error == null) {
                    if (!context.mounted) return;
                    ref
                        .read(noticeServiceProvider)
                        .success(context.l10n.common_appointmentDeleted);
                    onClose();
                  }
                },
          icon: const Icon(Icons.delete_outline, size: 15),
          label: Text(context.l10n.calendar_deleteAppointment),
        ),
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
              context.l10n.common_edit,
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
  const _Header({required this.appointment, required this.status});

  final AppointmentRecord appointment;
  final AppointmentStatus status;

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
          StatusChip(status: status),
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
              if (appointment.repeat != RepeatInterval.none)
                _IconLabel(
                  icon: Icons.repeat,
                  text: repeatIntervalLabel(context.l10n, appointment.repeat),
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
  const _MaterialsRow({required this.items});

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

class _EmployeesView extends ConsumerWidget {
  const _EmployeesView({required this.appointment});

  final AppointmentRecord appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedEmployees = ref.watch(
      eventDetailsControllerProvider(
        appointment,
      ).select((s) => s.selectedEmployees),
    );
    if (selectedEmployees.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp16),
        DetailsSectionRow(
          label: context.l10n.common_employees,
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
    final failedCount = failure?.failedCount ?? 0;
    final hasPhotos =
        existingImages.isNotEmpty || newImages.isNotEmpty || failedCount > 0;
    if (!hasPhotos) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp16),
        DetailsSectionRow(
          label: context.l10n.calendar_pictures,
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
