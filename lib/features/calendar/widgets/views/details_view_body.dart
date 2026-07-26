import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/details_action_bar.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_leaf_widgets.dart';
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
        // Cancelled visits keep the edit affordance; only `showActions` gates it.
        if (showActions)
          Align(
            alignment: compactHeader
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: DetailsEditChip(onTap: notifier.enterEditing),
          ),
        DetailsHeader(
          appointment: appointment,
          status: data.displayStatus,
          compact: compactHeader,
        ),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        _ClientSection(
          clientName: data.clientName,
          phone: data.phone,
          displayAddress: displayAddress,
          onCall: onCall,
          onDirections: onDirections,
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
          DetailsMaterialsRow(items: data.materials),
        ],
        DetailsEmployeesView(appointment: appointment),
        DetailsPhotosView(
          appointment: appointment,
          isCancelled: data.isCancelled,
          onRetry: notifier.enterEditing,
        ),
        DetailsActionBar(
          hasStarted: data.hasStarted,
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
    final outcome = await notifier.markAsDone(appointment);
    if (!context.mounted) return;
    _onStatusOutcome(
      context,
      ref,
      outcome,
      successMessage: context.l10n.common_appointmentMarkedAsDone,
    );
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
    final outcome = await notifier.cancelAppointment(appointment);
    if (!context.mounted) return;
    _onStatusOutcome(
      context,
      ref,
      outcome,
      successMessage: context.l10n.common_appointmentCancelled,
    );
  }

  /// Surfaces a status write's result; [EventDetailsActionBusy] stays silent
  /// since the guard skipped the write and the sheet stays open.
  void _onStatusOutcome(
    BuildContext context,
    WidgetRef ref,
    EventDetailsActionOutcome outcome, {
    required String successMessage,
  }) {
    switch (outcome) {
      case EventDetailsActionBusy():
        return;
      case EventDetailsActionFailed(:final error):
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
      case EventDetailsActionOk():
        ref.read(noticeServiceProvider).success(successMessage);
        onClose();
    }
  }
}

/// Pure-data derivations for [DetailsViewBody], computed once per build and
/// context-free; the layout flag (`compactHeader`) and ref-dependent
/// callbacks stay in `build`.
class _DetailsViewData {
  const _DetailsViewData({
    required this.displayStatus,
    required this.isCancelled,
    required this.isDone,
    required this.hasStarted,
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
    // Real stored status gates the actions (mark-done/cancel/edit); the
    // time-derived one drives the header chip so it matches the card.
    final displayStatus = AppointmentStatus.fromRaw(appointment.displayStatus);
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
      displayStatus: displayStatus,
      isCancelled: status.isCancelled,
      isDone: status.isDone,
      // Gates "Mark as complete" on the visit having STARTED, not on it being
      // today, so employees on multi-day/overnight visits aren't stuck without
      // a status surface — rules allow an assignee's `status:'done'` write with no date restriction.
      hasStarted: !appointment.startTime.isAfter(now),
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

  final AppointmentStatus displayStatus;
  final bool isCancelled;
  final bool isDone;
  final bool hasStarted;
  final String clientName;
  final String phone;
  final String displayAddress;
  final String notes;
  final List<String> materials;
  final List<ClientContact> extraContacts;
}

/// Quick-actions row + client info card (name/phone/address); call and
/// directions callbacks are resolved in the parent's `build` where `ref`
/// lives, and a null callback hides its affordance.
class _ClientSection extends StatelessWidget {
  const _ClientSection({
    required this.clientName,
    required this.phone,
    required this.displayAddress,
    required this.onCall,
    required this.onDirections,
  });

  final String clientName;
  final String phone;
  final String displayAddress;
  final VoidCallback? onCall;
  final VoidCallback? onDirections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onCall != null || onDirections != null) ...[
          QuickActionsRow(
            buttons: [
              if (onCall != null)
                QuickActionButton(
                  icon: Icons.phone_outlined,
                  label: context.l10n.clients_call,
                  onTap: onCall!,
                ),
              if (onDirections != null)
                QuickActionButton(
                  icon: Icons.directions_outlined,
                  label: context.l10n.clients_directions,
                  onTap: onDirections!,
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
              text: clientName,
              emphasize: true,
            ),
            if (phone.isNotEmpty)
              InfoCardRow(
                icon: Icons.phone_outlined,
                text: phone,
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
      ],
    );
  }
}
