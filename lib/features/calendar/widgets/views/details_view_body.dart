import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/domain/day_off_reason.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_prefill.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/domain/policies/push_back_options.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/busy_conflict_dialog.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/cancel_appointment_dialog.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/features/calendar/widgets/views/details_action_bar.dart';
import 'package:scheduling/features/calendar/widgets/views/details_field_record_view.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_leaf_widgets.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/cards/client_contacts_cards.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/key_value_panel.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/quick_action_button.dart';

class DetailsViewBody extends ConsumerWidget {
  const DetailsViewBody({
    required this.appointment,
    required this.showActions,
    required this.onClose,
    super.key,
    this.onBookAgain,
  });

  final AppointmentRecord appointment;
  final bool showActions;
  final VoidCallback onClose;

  /// Hands a "book again" draft to the host, which closes this view and opens
  /// the add sheet with it.
  final ValueChanged<AppointmentPrefill>? onBookAgain;

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
    // Push back is the admin's, on a job that still has a time to move; an
    // all-day block has no clock to shift and a closed one nothing to delay.
    final pushBackOptions = pushBackOptionsFor(appointment.startTime);
    final onPushBack =
        showActions &&
            !data.isClosed &&
            !appointment.isAllDay &&
            pushBackOptions.isNotEmpty
        ? () => _onPushBack(context, ref, notifier, pushBackOptions)
        : null;
    // Resolved once: it gates the field record below AND the Start button.
    final canRecordFieldWork = _canRecordFieldWork(ref, appointment);
    // Book again is the admin's, on any client job — a repeat callback most
    // often follows a FINISHED visit, so a closed job offers it too.
    final bookAgain =
        onBookAgain != null &&
            showActions &&
            !appointment.isPersonal &&
            appointment.clientId.trim().isNotEmpty
        ? () => onBookAgain!(
            AppointmentPrefill.bookAgain(
              appointment,
              client: client ?? placeholderClient(appointment),
            ),
          )
        : null;

    // TIME OFF is its own body: it has no client, no address, no materials and
    // no photos, and no lifecycle to act on — so it renders who it is for,
    // which days, and the note, and nothing else.
    if (appointment.isTimeOff) {
      return _DayOffBody(
        appointment: appointment,
        notes: data.notes,
        showActions: showActions,
        onEdit: notifier.enterEditing,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cancelled visits still show the edit affordance — `showActions` is
        // the only thing that gates it.
        if (showActions && !data.isDone)
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
        // The time record outlives the job; a cancelled one has no work to
        // time.
        if (data.hasTimeRecord && !data.isCancelled)
          DetailsTimeRecordRow(
            startedAt: appointment.startedAt,
            completedAt: appointment.completedAt,
          ),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        _ClientSection(
          isPersonal: appointment.isPersonal,
          clientName: data.clientName,
          phone: data.phone,
          displayAddress: displayAddress,
          notes: data.notes,
          onCall: onCall,
          onDirections: onDirections,
          onPushBack: onPushBack,
        ),
        ClientContactsCards(contacts: data.extraContacts, collapsible: true),
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
        // Offered to a NON-ADMIN ASSIGNEE only — exactly the set the crew
        // branches of `firestore.rules` admit, so the surface and the rule
        // cannot disagree about who may write.
        if (canRecordFieldWork)
          DetailsFieldRecordView(appointment: appointment),
        DetailsActionBar(
          isDone: data.isDone,
          isCancelled: data.isCancelled,
          isInProgress: data.isInProgress,
          isSaving: isSaving,
          showCancel: showActions,
          onEdit: showActions ? notifier.enterEditing : null,
          // Anyone who may close the job may start it; a personal block has no
          // arrival to record.
          onStart:
              (showActions || canRecordFieldWork) && !appointment.isPersonal
              ? () => _onStart(context, ref, notifier)
              : null,
          onMarkDone: () => _onMarkDone(context, ref, notifier),
          onCancel: () => _onCancel(context, ref, notifier),
          onBookAgain: bookAgain,
        ),
      ],
    );
  }

  /// Whether the viewer is a non-admin assignee of [appointment].
  static bool _canRecordFieldWork(
    WidgetRef ref,
    AppointmentRecord appointment,
  ) {
    final identity = ref.watch(activeUserIdentityProvider).value;
    if (identity == null || identity.role == 'admin') return false;
    return appointment.employeeIds.contains(identity.docId);
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

  Future<void> _onStart(
    BuildContext context,
    WidgetRef ref,
    EventDetailsController notifier,
  ) async {
    final outcome = await notifier.startJob(appointment);
    if (!context.mounted) return;
    _onStatusOutcome(
      context,
      ref,
      outcome,
      successMessage: context.l10n.calendar_jobStarted,
      // Mark-done and cancel close because the job is FINISHED.
      closeOnSuccess: false,
    );
  }

  /// Push back: pick an offset, shift the job, and — like the edit form — let
  /// the admin push through a clash the shift creates.
  Future<void> _onPushBack(
    BuildContext context,
    WidgetRef ref,
    EventDetailsController notifier,
    List<int> options,
  ) async {
    final l10n = context.l10n;
    // Resolved before the awaits: this sheet can be dismissed mid-flight.
    final notices = ref.read(noticeServiceProvider);
    final minutes = await showAdaptiveActionSheet<int>(
      context,
      title: l10n.calendar_pushBackTitle,
      actions: [
        for (final m in options)
          AdaptiveSheetAction(value: m, label: l10n.calendar_pushBackBy(m)),
      ],
    );
    if (minutes == null || !context.mounted) return;

    var outcome = await notifier.delayAppointment(
      appointment,
      minutes: minutes,
    );
    if (!context.mounted) return;
    if (outcome is EventDetailsBusyEmployees) {
      final confirmed = await showBusyConflictDialog(
        context,
        busyEmployees: outcome.busyEmployees,
        start: outcome.start,
        end: outcome.end,
      );
      if (!confirmed || !context.mounted) return;
      outcome = await notifier.delayAppointment(
        appointment,
        minutes: minutes,
        forceBusy: true,
      );
      if (!context.mounted) return;
    }
    switch (outcome) {
      case EventDetailsSaved():
        notices.success(l10n.calendar_pushedBack(minutes));
        onClose();
      case EventDetailsFailed(:final error):
        notices.error(
          composeErrorNotice(
            context,
            intro: l10n.error_introSaveAppointment,
            error: error,
          ),
        );
      // Busy skipped the write; a clash the admin declined stays as it was.
      case EventDetailsSaveBusy() ||
          EventDetailsInvalid() ||
          EventDetailsBusyEmployees():
        break;
    }
  }

  Future<void> _onCancel(
    BuildContext context,
    WidgetRef ref,
    EventDetailsController notifier,
  ) async {
    final choice = await showCancelAppointmentDialog(
      context,
      // One day of a run offers the tail; anything else is a plain confirm.
      isRun: appointment.isRunMember,
    );
    if (choice == null || !context.mounted) return;
    final outcome = await notifier.cancelAppointment(
      appointment,
      includeFuture: choice == SeriesScopeChoice.thisAndFuture,
    );
    if (!context.mounted) return;
    _onStatusOutcome(
      context,
      ref,
      outcome,
      successMessage: context.l10n.common_appointmentCancelled,
    );
  }

  /// Surfaces the result of a status write.
  void _onStatusOutcome(
    BuildContext context,
    WidgetRef ref,
    EventDetailsActionOutcome outcome, {
    required String successMessage,
    bool closeOnSuccess = true,
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
                error: error,
              ),
            );
      case EventDetailsActionOk():
        ref.read(noticeServiceProvider).success(successMessage);
        if (closeOnSuccess) onClose();
    }
  }
}

/// Pure-data derivations for [DetailsViewBody].
class _DayOffBody extends StatelessWidget {
  const _DayOffBody({
    required this.appointment,
    required this.notes,
    required this.showActions,
    required this.onEdit,
  });

  final AppointmentRecord appointment;
  final String notes;
  final bool showActions;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final names = [
      for (final name in appointment.employeeNames)
        if (name.trim().isNotEmpty) name.trim(),
    ];
    final subject = names.isNotEmpty ? names.join(', ') : appointment.title;
    final reason = dayOffReason(
      title: appointment.title,
      hasSubject: names.isNotEmpty,
      placeholders: personalTitlePlaceholders,
    );
    final days = runLengthDays(
      appointment.startTime,
      appointment.endTime,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showActions)
          Align(
            alignment: context.isCompact
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: DetailsEditChip(onTap: onEdit),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reason ?? subject, style: theme.textTheme.headlineLarge),
              if (reason != null) ...[
                const SizedBox(height: AppSpacing.sp4),
                Text(
                  subject,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.palette.textTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sp8),
              Text(
                DateUtilsHelper.formatWhenLine(
                  appointment.startTime,
                  appointment.endTime,
                  allDayLabel: l10n.calendar_dayOff,
                  lastDay: appointment.endTime,
                ),
                style: theme.monoType.data,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        KeyValuePanel(
          rows: [
            KeyValueRow(
              label: l10n.calendar_dayOff.toUpperCase(),
              value: l10n.calendar_dayOffLength(days),
            ),
            if (notes.trim().isNotEmpty)
              KeyValueRow(
                label: l10n.calendar_notes.toUpperCase(),
                value: notes.trim(),
              ),
          ],
        ),
      ],
    );
  }
}

class _DetailsViewData {
  const _DetailsViewData({
    required this.displayStatus,
    required this.isCancelled,
    required this.isDone,
    required this.isInProgress,
    required this.hasTimeRecord,
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
    // The actions (mark-done/cancel/edit) are gated on the real stored status,
    // while the header chip uses the time-derived one instead, so it matches
    // what the card shows.
    final displayStatus = AppointmentStatus.fromRaw(appointment.displayStatus);
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
      isInProgress: status == AppointmentStatus.inProgress,
      hasTimeRecord:
          appointment.startedAt != null || appointment.completedAt != null,
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
  final bool isInProgress;
  final bool hasTimeRecord;

  bool get isClosed => isDone || isCancelled;
  final String clientName;
  final String phone;
  final String displayAddress;
  final String notes;
  final List<String> materials;
  final List<ClientContact> extraContacts;
}

/// Quick-actions row plus the client panel (name/phone/address/notes).
class _ClientSection extends StatelessWidget {
  const _ClientSection({
    required this.isPersonal,
    required this.clientName,
    required this.phone,
    required this.displayAddress,
    required this.notes,
    required this.onCall,
    required this.onDirections,
    required this.onPushBack,
  });

  /// A personal job has no client, so the client row names it as personal
  /// instead of rendering an empty value.
  final bool isPersonal;
  final String clientName;
  final String phone;
  final String displayAddress;
  final String notes;
  final VoidCallback? onCall;
  final VoidCallback? onDirections;

  /// Admin-only, on an open timed job — see the gate in the parent's build.
  final VoidCallback? onPushBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onCall != null || onDirections != null || onPushBack != null) ...[
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
              if (onPushBack != null)
                QuickActionButton(
                  icon: Icons.update_rounded,
                  label: context.l10n.calendar_pushBack,
                  onTap: onPushBack!,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sp24),
        ],
        // The mono key column labels the content, so this panel needs no
        // SectionLabel above it.
        KeyValuePanel(
          rows: [
            KeyValueRow(
              label: context.l10n.calendar_client.toUpperCase(),
              value: isPersonal ? context.l10n.calendar_personal : clientName,
            ),
            if (phone.isNotEmpty)
              KeyValueRow(
                label: context.l10n.clients_phone.toUpperCase(),
                value: phone,
                emphasize: true,
                onTap: onCall,
              ),
            if (displayAddress.isNotEmpty)
              KeyValueRow(
                label: context.l10n.common_address.toUpperCase(),
                value: displayAddress,
                emphasize: true,
                onTap: onDirections,
                semanticLabel:
                    '$displayAddress, ${context.l10n.maps_openAddressWith}',
              ),
            if (notes.isNotEmpty)
              KeyValueRow(
                label: context.l10n.calendar_notes.toUpperCase(),
                value: notes,
              ),
          ],
        ),
      ],
    );
  }
}
