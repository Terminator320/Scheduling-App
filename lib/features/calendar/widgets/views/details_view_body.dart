import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/widgets/fields/repeat_interval_picker.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/views/details_action_bar.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_widgets.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/cards/client_contacts_cards.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/info_card.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
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
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    final client = ref.watch(provider.select((s) => s.client));
    final isSaving = ref.watch(provider.select((s) => s.isSaving));
    final notifier = ref.read(provider.notifier);

    final data = _DetailsViewData.from(appointment, client);
    final compactHeader = context.isCompact;
    final displayAddress = data.displayAddress;
    final onCall = data.phone.isNotEmpty
        ? () => launchPhoneCall(context, ref, data.phone)
        : null;
    final onDirections = appointment.address.isNotEmpty
        ? () => AddressMapLauncher.showMapChoices(
            context,
            address: appointment.address,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showActions && !data.isCancelled)
          Align(
            alignment: compactHeader
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: _EditChip(onTap: notifier.enterEditing),
          ),
        _Header(
          appointment: appointment,
          status: data.status,
          compact: compactHeader,
        ),
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
          rows: [
            InfoCardRow(
              icon: Icons.person_outline,
              text: data.clientName,
              emphasize: true,
            ),
            if (data.phone.isNotEmpty)
              InfoCardRow(
                icon: Icons.phone_outlined,
                text: data.phone,
                onTap: onCall,
                trailingIcon: Icons.chevron_right,
              ),
            if (displayAddress.isNotEmpty)
              InfoCardRow(
                icon: Icons.location_on_outlined,
                text: displayAddress,
                onTap: onDirections,
                trailingIcon: Icons.open_in_new,
                semanticLabel:
                    '$displayAddress, ${context.l10n.maps_openAddressWith}',
              ),
          ],
        ),
        ClientContactsCards(contacts: data.extraContacts, collapsible: true),
        if (data.notes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sp16),
          DetailsSectionRow(
            label: context.l10n.calendar_notes,
            value: data.notes,
          ),
        ],
        if (data.materials.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sp16),
          _MaterialsRow(items: data.materials),
        ],
        _EmployeesView(appointment: appointment),
        _PhotosView(
          appointment: appointment,
          isCancelled: data.isCancelled,
          onRetry: notifier.enterEditing,
        ),
        DetailsActionBar(
          isToday: data.isToday,
          isDone: data.isDone,
          isCancelled: data.isCancelled,
          isSaving: isSaving,
          showCancel: showActions,
          onMarkDone: () => _onMarkDone(context, ref, notifier),
          onCancel: () => _onCancel(context, ref, notifier),
        ),
      ],
    );
  }

  Future<void> _onMarkDone(
    BuildContext context,
    WidgetRef ref,
    EventDetailsController notifier,
  ) async {
    final error = await notifier.markAsDone(appointment);
    if (!context.mounted) return;
    if (error != null) {
      _notifyStatusError(context, ref, error);
      return;
    }
    ref
        .read(noticeServiceProvider)
        .success(context.l10n.common_appointmentMarkedAsDone);
    onClose();
  }

  Future<void> _onCancel(
    BuildContext context,
    WidgetRef ref,
    EventDetailsController notifier,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.calendar_cancelAppointment,
      message: context.l10n.calendar_cancelledJobsAreSavedToHistory,
      confirmLabel: context.l10n.calendar_cancelAppointment,
    );
    if (!confirmed || !context.mounted) return;
    final error = await notifier.cancelAppointment(appointment);
    if (!context.mounted) return;
    if (error != null) {
      _notifyStatusError(context, ref, error);
      return;
    }
    ref
        .read(noticeServiceProvider)
        .success(context.l10n.common_appointmentCancelled);
    onClose();
  }

  void _notifyStatusError(BuildContext context, WidgetRef ref, Object error) {
    ref
        .read(noticeServiceProvider)
        .error(
          composeErrorNotice(
            context,
            intro: context.l10n.error_introUpdateAppointmentStatus,
            tag: 'APPT-STATUS',
            error: error,
          ),
        );
  }
}

/// Pure-data derivations for [DetailsViewBody], computed once per build.
/// Context-free — the layout flag (`compactHeader`) and ref-dependent
/// callbacks stay in `build`.
class _DetailsViewData {
  const _DetailsViewData({
    required this.status,
    required this.isCancelled,
    required this.isDone,
    required this.isToday,
    required this.clientName,
    required this.phone,
    required this.displayAddress,
    required this.notes,
    required this.materials,
    required this.extraContacts,
  });

  factory _DetailsViewData.from(
    AppointmentRecord appointment,
    ClientRecord? client,
  ) {
    final status = AppointmentStatus.fromRaw(appointment.status);
    final now = DateTime.now();
    final phone = (client?.phone.isNotEmpty ?? false)
        ? client!.phone
        : appointment.clientPhone;
    final materials = appointment.materialsNeeded
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    return _DetailsViewData(
      status: status,
      isCancelled: status.isCancelled,
      isDone: status.isDone,
      isToday:
          appointment.startTime.year == now.year &&
          appointment.startTime.month == now.month &&
          appointment.startTime.day == now.day,
      clientName: client?.displayName ?? appointment.clientName,
      phone: phone,
      displayAddress: appointment.address.isNotEmpty
          ? AddressParser.canonicalToDisplay(appointment.address)
          : '',
      notes: appointment.notes,
      materials: materials,
      extraContacts: (client?.contacts ?? const <ClientContact>[]).toList(),
    );
  }

  final AppointmentStatus status;
  final bool isCancelled;
  final bool isDone;
  final bool isToday;
  final String clientName;
  final String phone;
  final String displayAddress;
  final String notes;
  final List<String> materials;
  final List<ClientContact> extraContacts;
}

class _EditChip extends StatelessWidget {
  const _EditChip({required this.onTap});

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

class _Header extends StatelessWidget {
  const _Header({
    required this.appointment,
    required this.status,
    required this.compact,
  });

  final AppointmentRecord appointment;
  final AppointmentStatus status;
  final bool compact;

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
            style: compact
                ? theme.textTheme.headlineSmall
                : theme.textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sp8),
          StatusChip(status: status),
          const SizedBox(height: AppSpacing.sp8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 6,
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
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
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
        EventDetailsKey(appointment),
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
