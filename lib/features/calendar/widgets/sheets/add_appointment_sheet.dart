import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/adaptive/adaptive_pickers.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/application/add_event_controller.dart';
import 'package:scheduling/features/calendar/domain/models/job_template.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/utils/appointment_draft_defaults.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/busy_conflict_dialog.dart';
import 'package:scheduling/features/calendar/widgets/sections/appointment_form_fields.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/sheets/image_source_picker.dart';
import 'package:scheduling/features/calendar/widgets/sheets/inline_add_client_host.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/domain/tour_steps.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/sheets/form_sheet_frame.dart';

class AddEventSheet extends ConsumerStatefulWidget {
  const AddEventSheet({super.key, this.initialDate, this.initialClient});

  final DateTime? initialDate;

  /// Pre-seeds the client, for "Add and book a job" and the client detail's
  /// Book job tile.
  final ClientRecord? initialClient;

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet>
    with InlineAddClientHost {
  final _controllers = AppointmentFormControllers(
    title: TextEditingController(),
    date: TextEditingController(),
    endDate: TextEditingController(),
    startTime: TextEditingController(),
    endTime: TextEditingController(),
    clientSearch: TextEditingController(),
    address: TextEditingController(),
    notes: TextEditingController(),
    materials: TextEditingController(),
  );
  final _clientSearchDebounce = Debouncer(const Duration(milliseconds: 300));
  late final _provider = addEventControllerProvider(widget.initialDate);

  // Admin-only surface: this sheet is only reachable from the calendar FAB
  // and the client detail's Book job, both admin-gated.
  final _tour = TourSteps(
    const FormTour(TourForm.addAppointment),
    isAdmin: true,
  );

  AddEventController get _notifier => ref.read(_provider.notifier);

  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialDate;
    if (initialDate != null) {
      _controllers.date.text = DateUtilsHelper.formatDate(initialDate);
      _controllers.endDate.text = _controllers.date.text;
    }
    final client = widget.initialClient;
    if (client != null) {
      _controllers.clientSearch.text = client.displayName;
      // Deferred: the controller is a family provider that must be built before
      // the first read, and selectClient also settles the address field.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _notifier.selectClient(client);
      });
    }
  }

  @override
  void dispose() {
    _clientSearchDebounce.dispose();
    _controllers.dispose();
    super.dispose();
  }

  void _onClientSearchChanged(String query) {
    if (query.trim().isEmpty) {
      _clientSearchDebounce.cancel();
      _notifier.searchClients('');
      return;
    }
    _clientSearchDebounce.run(() => _notifier.searchClients(query));
  }

  Future<void> _pickDate() async {
    final state = ref.read(_provider);
    final picked = await showAdaptiveDatePicker(
      context,
      initialDate: state.selectedDate ?? DateTime.now(),
      firstDate: AppointmentDraftDefaults.datePickerFirstDate,
      lastDate: AppointmentDraftDefaults.datePickerLastDate,
    );
    if (picked == null || !mounted) return;
    _controllers.date.text = DateUtilsHelper.formatDate(picked);
    _notifier.selectDate(picked);
    // selectDate mirrors or shifts the end date, and the end row renders the
    // controller text — so it has to follow, or it goes stale.
    final shifted = ref.read(_provider).endDate;
    if (shifted != null) {
      _controllers.endDate.text = DateUtilsHelper.formatDate(shifted);
    }
  }

  Future<void> _pickEndDate() async {
    final state = ref.read(_provider);
    final picked = await showAdaptiveDatePicker(
      context,
      initialDate: state.endDate ?? state.selectedDate ?? DateTime.now(),
      // Never offer a date before the start: an end date that precedes it is
      // unbookable, so it shouldn't be reachable in the picker either.
      firstDate:
          state.selectedDate?.dateOnly ??
          AppointmentDraftDefaults.datePickerFirstDate,
      lastDate: AppointmentDraftDefaults.datePickerLastDate,
    );
    if (picked == null || !mounted) return;
    _controllers.endDate.text = DateUtilsHelper.formatDate(picked);
    _notifier.selectEndDate(picked);
  }

  Future<void> _pickStartTime() async {
    final stateBefore = ref.read(_provider);
    final picked = await showAdaptiveTimePicker(
      context,
      initialTime: stateBefore.selectedStartTime,
    );
    if (picked == null || !mounted) return;
    _controllers.startTime.text = picked.format(context);
    if (!stateBefore.endTimeWasPickedManually) {
      final autoEnd = AppointmentDraftDefaults.defaultEndTime(picked);
      _controllers.endTime.text = autoEnd.format(context);
    }
    _notifier.selectStartTime(picked);
  }

  Future<void> _pickEndTime() async {
    final state = ref.read(_provider);
    final picked = await showAdaptiveTimePicker(
      context,
      initialTime: state.selectedEndTime,
    );
    if (picked == null || !mounted) return;
    _controllers.endTime.text = picked.format(context);
    _notifier.selectEndTime(picked);
  }

  // Quick-fills the title from the job type, and the end time from the template's duration if a start time has already been picked.
  void _applyTemplate(JobTemplate template) {
    _controllers.title.text = jobTemplateLabel(context.l10n, template);
    final start = ref.read(_provider).selectedStartTime;
    if (start != null) {
      final endMinutes = template.endMinutesOfDay(
        start.hour * 60 + start.minute,
      );
      final end = TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);
      _controllers.endTime.text = end.format(context);
      _notifier.selectEndTime(end);
    }
  }

  int _spanLength(AddEventState state) =>
      runLengthDays(state.selectedDate, state.endDate);

  bool _isOvernight(AddEventState state) {
    final start = state.selectedStartTime;
    final end = state.selectedEndTime;
    if (state.isAllDay || start == null || end == null) return false;
    return isOvernightWindow(start, end);
  }

  Future<void> _pickImages() async {
    final picked = await pickAppointmentImages(context, ref);
    // The longest await in the app — an OS action sheet and then the
    // camera/Photos picker. The notifier is autoDispose.family, so calling it
    // after the sheet was torn down under the picker throws a StateError out
    // of an unawaited callback, which is filed as FATAL.
    if (!mounted) return;
    if (picked.isNotEmpty) _notifier.addImages(picked);
  }

  Future<void> _submit() async {
    // An unnamed personal block saves as "Personal" — the stored title is what
    // the card, the widget, Siri and the push text all read.
    final title = _controllers.title.text.trim().isEmpty
        ? (ref.read(_provider).isPersonal ? context.l10n.calendar_personal : '')
        : _controllers.title.text;

    Future<AddEventSubmitOutcome> attempt({bool forceBusy = false}) =>
        _notifier.submit(
          title: title,
          address: AddressParser.toCanonical(_controllers.address.text),
          notes: _controllers.notes.text,
          materialsNeeded: _controllers.materials.text,
          forceBusy: forceBusy,
        );

    var outcome = await attempt();
    if (!mounted) return;
    if (outcome is AddEventBusyEmployees) {
      final confirmed = await showBusyConflictDialog(
        context,
        busyEmployees: outcome.busyEmployees,
        start: outcome.start,
        end: outcome.end,
      );
      if (!confirmed || !mounted) return;
      outcome = await attempt(forceBusy: true);
      if (!mounted) return;
    }
    switch (outcome) {
      case AddEventSubmitted(:final appointment, :final futureBookings):
        ref
            .read(noticeServiceProvider)
            .success(
              futureBookings > 0
                  ? context.l10n.calendar_appointmentCreatedWithRepeats(
                      futureBookings,
                    )
                  : context.l10n.common_appointmentCreated,
            );
        Navigator.pop(context, appointment);
      case AddEventFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introCreateAppointment,
                error: error,
              ),
            );
      case AddEventInvalid() || AddEventBusyEmployees():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final allEmployees =
        ref.watch(employeesStreamProvider).asData?.value ?? const [];
    // One length feeds both the flag and the label, so they can't disagree:
    // the run-length string is a plain interpolation, and a multi-day flag
    // paired with a length of 1 would render "1 days".
    final spanLength = _spanLength(state);

    return FeatureTourHost(
      scope: _tour.scope,
      isAdmin: true,
      stepKeys: _tour.keys,
      // The form scrolls, so below-fold targets need building before
      // isTargetRendered looks for them.
      autoScroll: true,
      child: FormSheetFrame(
        title: context.l10n.calendar_newAppointment,
        primaryLabel: context.l10n.common_save,
        isBusy: state.isSubmitting,
        onPrimary: _submit,
        headerTourWrap: (child) => _tour.stepIf(TourStepId.apptSave, child),
        scrollCacheExtent: kTourScrollCacheExtent,
        children: [
          AppointmentFormFields(
            controllers: _controllers,
            tourWrap: _tour.stepIf,
            allEmployees: allEmployees,
            selectedClient: state.selectedClient,
            clientResults: state.clientResults,
            isSearchingClient: state.isSearchingClient,
            selectedEmployees: state.selectedEmployees,
            repeat: state.repeat,
            useCustomAddress: state.useCustomAddress,
            isPersonal: state.isPersonal,
            onPersonalChanged: (value) => _notifier.setPersonal(value: value),
            isAllDay: state.isAllDay,
            onAllDayChanged: (value) => _notifier.setAllDay(value: value),
            errors: state.errors,
            employeeLabel: context.l10n.calendar_assignEmployee,
            employeeRequired: true,
            materialsHint: context.l10n.calendar_typeTheMaterialsHere,
            onApplyTemplate: _applyTemplate,
            onSearchClients: _onClientSearchChanged,
            onSelectClient: _notifier.selectClient,
            onClearClient: _notifier.clearClient,
            onRequestAddClient: requestAddClient,
            onToggleEmployee: _notifier.toggleEmployee,
            onPickDate: _pickDate,
            onPickEndDate: _pickEndDate,
            isMultiDay: spanLength > 1,
            isOvernight: _isOvernight(state),
            spanLength: spanLength,
            onPickStartTime: _pickStartTime,
            onPickEndTime: _pickEndTime,
            onSelectRepeat: _notifier.selectRepeat,
            onUseCustomAddress: (value) =>
                _notifier.setUseCustomAddress(value: value),
            photosSection: PhotoPickerSection(
              existingImages: const [],
              newImages: state.selectedImages,
              isEditing: true,
              onPickImages: _pickImages,
              onRemoveExisting: (_) {},
              onRemoveNew: _notifier.removeImage,
            ),
          ),
        ],
      ),
    );
  }
}
