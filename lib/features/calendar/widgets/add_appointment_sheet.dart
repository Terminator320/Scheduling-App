import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/calendar/application/add_event_controller.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/utils/appointment_draft_defaults.dart';
import 'package:scheduling/features/calendar/utils/cupertino_time_picker.dart';
import 'package:scheduling/features/calendar/widgets/appointment_address_field.dart';
import 'package:scheduling/features/calendar/widgets/busy_conflict_dialog.dart';
import 'package:scheduling/features/calendar/widgets/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/photo_picker_section.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/client_search_field.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

class AddEventSheet extends ConsumerStatefulWidget {
  const AddEventSheet({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet> {
  final _titleController = TextEditingController();
  final _dateController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _clientSearchController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final _materialsController = TextEditingController();
  Timer? _clientSearchDebounce;
  late final _provider = addEventControllerProvider(widget.initialDate);

  AddEventController get _notifier => ref.read(_provider.notifier);

  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialDate;
    if (initialDate != null) {
      _dateController.text = DateUtilsHelper.formatDate(initialDate);
    }
  }

  @override
  void dispose() {
    _clientSearchDebounce?.cancel();
    _titleController.dispose();
    _dateController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _clientSearchController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _materialsController.dispose();
    super.dispose();
  }

  void _onClientSearchChanged(String query) {
    _clientSearchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _notifier.searchClients('');
      return;
    }
    _clientSearchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _notifier.searchClients(query),
    );
  }

  void _selectClient(ClientRecord client) {
    _clientSearchController.text = client.displayName;
    _addressController.text = AddressParser.canonicalToDisplay(client.address);
    _notifier.selectClient(client);
  }

  void _clearClient() {
    _clientSearchController.clear();
    _addressController.clear();
    _notifier.clearClient();
  }

  Future<void> _pickDate() async {
    final state = ref.read(_provider);
    final picked = await showDatePicker(
      context: context,
      initialDate: state.selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _dateController.text = DateUtilsHelper.formatDate(picked);
    _notifier.selectDate(picked);
  }

  Future<void> _pickStartTime() async {
    final stateBefore = ref.read(_provider);
    final picked = await showCupertinoTimePicker(
      context,
      initialTime: stateBefore.selectedStartTime,
    );
    if (picked == null || !mounted) return;
    _startTimeController.text = picked.format(context);
    if (!stateBefore.endTimeWasPickedManually) {
      final autoEnd = AppointmentDraftDefaults.defaultEndTime(picked);
      _endTimeController.text = autoEnd.format(context);
    }
    _notifier.selectStartTime(picked);
  }

  Future<void> _pickEndTime() async {
    final state = ref.read(_provider);
    final picked = await showCupertinoTimePicker(
      context,
      initialTime: state.selectedEndTime,
    );
    if (picked == null || !mounted) return;
    _endTimeController.text = picked.format(context);
    _notifier.selectEndTime(picked);
  }

  Future<void> _pickImages() async {
    final picker = ref.read(imagePickerProvider);
    final picked = await picker.pickMultiImages();
    if (picked.isNotEmpty) _notifier.addImages(picked);
  }

  void _useClientAddress() {
    final client = ref.read(_provider).selectedClient;
    if (client == null) return;
    _addressController.text = AddressParser.canonicalToDisplay(client.address);
    _notifier.setUseCustomAddress(false);
  }

  Future<void> _submit() async {
    Future<AddEventSubmitOutcome> attempt({bool forceBusy = false}) =>
        _notifier.submit(
          title: _titleController.text,
          address: AddressParser.toCanonical(_addressController.text),
          notes: _notesController.text,
          materialsNeeded: _materialsController.text,
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
      case AddEventSubmitted(:final appointment):
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.common_appointmentCreated);
        Navigator.pop(context, appointment);
      case AddEventFailed():
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.error_somethingWentWrongCreatingTheAppointment);
      case AddEventInvalid() || AddEventBusyEmployees():
        break;
    }
  }

  String _errorText(AppointmentFormError key) {
    return switch (key) {
      AppointmentFormError.titleRequired => context.l10n.validation_titleIsRequired,
      AppointmentFormError.dateRequired => context.l10n.validation_pleaseSelectADate,
      AppointmentFormError.startTimeRequired =>
        context.l10n.validation_pleaseSelectAStartTime,
      AppointmentFormError.endTimeRequired =>
        context.l10n.validation_pleaseSelectAnEndTime,
      AppointmentFormError.endTimeMustBeAfterStart =>
        context.l10n.calendar_mustBeAfterStartTime,
      AppointmentFormError.clientRequired => context.l10n.validation_pleaseSelectAClient,
      AppointmentFormError.employeesRequired =>
        context.l10n.validation_pleaseSelectAtLeastOneEmployee,
    };
  }

  String? _errorFor(Map<String, AppointmentFormError> errors, String field) {
    final key = errors[field];
    return key == null ? null : _errorText(key);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final allEmployees =
        ref.watch(employeesStreamProvider).asData?.value ?? const [];

    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: AppSpacing.sp16,
            right: AppSpacing.sp16,
            top: AppSpacing.sp12,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.sp24,
          ),
          children: [
            const SheetHandle(),
            const SizedBox(height: AppSpacing.sp16),
            Text(
              sheetContext.l10n.calendar_newAppointment,
              style: Theme.of(sheetContext).textTheme.headlineLarge,
            ),
            const SizedBox(height: AppSpacing.sp16),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sp16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: sheetContext.l10n.calendar_serviceTitle,
                hint: sheetContext.l10n.calendar_eGPlumbingRepair,
                controller: _titleController,
                required: true,
                maxLength: TextLimits.appointmentTitle,
                errorText: _errorFor(state.errors, 'title'),
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),
            formLabel(sheetContext, sheetContext.l10n.calendar_client, required: true),
            SheetFocusScroll(
              child: ClientSearchField(
                controller: _clientSearchController,
                selectedClient: state.selectedClient,
                results: state.clientResults,
                isSearching: state.isSearchingClient,
                onChanged: _onClientSearchChanged,
                onSelect: _selectClient,
                onClear: _clearClient,
                errorText: _errorFor(state.errors, 'client'),
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),
            formLabel(
              sheetContext,
              sheetContext.l10n.calendar_assignEmployee,
              required: true,
            ),
            const SizedBox(height: 6),
            EmployeePicker(
              allEmployees: allEmployees,
              selectedEmployees: state.selectedEmployees,
              onToggle: _notifier.toggleEmployee,
              hasError: state.errors.containsKey('employees'),
            ),
            if (state.errors.containsKey('employees'))
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  _errorFor(state.errors, 'employees') ?? '',
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sp16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: sheetContext.l10n.calendar_date,
                hint: sheetContext.l10n.calendar_selectDate,
                controller: _dateController,
                required: true,
                readOnly: true,
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                errorText: _errorFor(state.errors, 'date'),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SheetFocusScroll(
                    child: LabeledTextField(
                      label: sheetContext.l10n.calendar_startTime,
                      hint: sheetContext.l10n.calendar_start,
                      controller: _startTimeController,
                      required: true,
                      readOnly: true,
                      errorText: _errorFor(state.errors, 'startTime'),
                      onTap: _pickStartTime,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sp12),
                Expanded(
                  child: SheetFocusScroll(
                    child: LabeledTextField(
                      label: sheetContext.l10n.calendar_endTime,
                      hint: sheetContext.l10n.calendar_end,
                      controller: _endTimeController,
                      required: true,
                      readOnly: true,
                      errorText: _errorFor(state.errors, 'endTime'),
                      onTap: _pickEndTime,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sp16),
            AppointmentAddressField(
              selectedClient: state.selectedClient,
              useCustomAddress: state.useCustomAddress,
              addressController: _addressController,
              onSwitchToCustom: () => _notifier.setUseCustomAddress(true),
              onUseClientAddress: _useClientAddress,
            ),
            const SizedBox(height: AppSpacing.sp16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: sheetContext.l10n.calendar_materialsNeeded,
                hint: sheetContext.l10n.calendar_typeTheMaterialsHere,
                controller: _materialsController,
                optional: true,
                maxLines: 2,
                maxLength: TextLimits.appointmentMaterials,
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: sheetContext.l10n.calendar_notes,
                hint: sheetContext.l10n.calendar_typeTheNoteHere,
                controller: _notesController,
                optional: true,
                maxLines: 2,
                maxLength: TextLimits.appointmentNotes,
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),
            formLabel(sheetContext, sheetContext.l10n.calendar_pictures, optional: true),
            PhotoPickerSection(
              existingImages: const [],
              newImages: state.selectedImages,
              isEditing: true,
              onPickImages: _pickImages,
              onRemoveExisting: (_) {},
              onRemoveNew: _notifier.removeImage,
            ),
            const SizedBox(height: AppSpacing.sp24),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: state.isSubmitting ? null : _submit,
              child: state.isSubmitting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(sheetContext).colorScheme.onPrimary,
                      ),
                    )
                  : Text(sheetContext.l10n.calendar_saveAppointment),
            ),
          ],
        );
      },
    );
  }
}
