import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/application/add_event_controller.dart';
import 'package:scheduling/features/calendar/utils/adaptive_pickers.dart';
import 'package:scheduling/features/calendar/utils/appointment_draft_defaults.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/busy_conflict_dialog.dart';
import 'package:scheduling/features/calendar/widgets/sections/appointment_form_fields.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/sheets/image_source_picker.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class AddEventSheet extends ConsumerStatefulWidget {
  const AddEventSheet({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet> {
  final _controllers = AppointmentFormControllers(
    title: TextEditingController(),
    date: TextEditingController(),
    startTime: TextEditingController(),
    endTime: TextEditingController(),
    clientSearch: TextEditingController(),
    address: TextEditingController(),
    notes: TextEditingController(),
    materials: TextEditingController(),
  );
  final _clientSearchDebounce = Debouncer(const Duration(milliseconds: 300));
  late final _provider = addEventControllerProvider(widget.initialDate);

  // Guards the inline add-client sheet against a double-tap: the sheet-from-
  // search settle delays the modal barrier ~80ms, leaving the trigger tappable,
  // so an unguarded second tap would stack a second sheet (duplicate client).
  bool _addingClient = false;

  AddEventController get _notifier => ref.read(_provider.notifier);

  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialDate;
    if (initialDate != null) {
      _controllers.date.text = DateUtilsHelper.formatDate(initialDate);
    }
  }

  @override
  void dispose() {
    _clientSearchDebounce.dispose();
    _controllers.dispose();
    super.dispose();
  }

  Future<ClientRecord?> _onRequestAddClient(String name) async {
    if (_addingClient) return null;
    _addingClient = true;
    try {
      return await showAddClientSheet(
        context,
        initialName: name,
        settleFocus: true,
      );
    } finally {
      if (mounted) _addingClient = false;
    }
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
    if (picked == null) return;
    _controllers.date.text = DateUtilsHelper.formatDate(picked);
    _notifier.selectDate(picked);
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

  Future<void> _pickImages() async {
    final picked = await pickAppointmentImages(context, ref);
    if (picked.isNotEmpty) _notifier.addImages(picked);
  }

  Future<void> _submit() async {
    Future<AddEventSubmitOutcome> attempt({bool forceBusy = false}) =>
        _notifier.submit(
          title: _controllers.title.text,
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
                tag: 'APPT-CREATE',
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

    return FormSheetScaffold(
      title: context.l10n.calendar_newAppointment,
      children: [
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        AppointmentFormFields(
          controllers: _controllers,
          allEmployees: allEmployees,
          selectedClient: state.selectedClient,
          clientResults: state.clientResults,
          isSearchingClient: state.isSearchingClient,
          selectedEmployees: state.selectedEmployees,
          repeat: state.repeat,
          useCustomAddress: state.useCustomAddress,
          errors: state.errors,
          employeeLabel: context.l10n.calendar_assignEmployee,
          employeeRequired: true,
          materialsHint: context.l10n.calendar_typeTheMaterialsHere,
          onSearchClients: _onClientSearchChanged,
          onSelectClient: _notifier.selectClient,
          onClearClient: _notifier.clearClient,
          onRequestAddClient: _onRequestAddClient,
          onToggleEmployee: _notifier.toggleEmployee,
          onPickDate: _pickDate,
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
        const SizedBox(height: AppSpacing.sp24),
        AnimatedLoadingButton(
          label: context.l10n.calendar_saveAppointment,
          isLoading: state.isSubmitting,
          onPressed: _submit,
          height: 48,
        ),
      ],
    );
  }
}
