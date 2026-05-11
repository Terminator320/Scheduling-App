import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
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
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

/// New-appointment sheet. Thin shell over [AddEventController]: holds the
/// `TextEditingController`s and the search-debounce `Timer` (UI primitives
/// whose lifecycle ties to the widget mount/unmount), and reads/dispatches
/// everything else through the controller.
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
    _addressController.text = client.address;
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
    _addressController.text = client.address;
    _notifier.setUseCustomAddress(false);
  }

  Future<void> _submit() async {
    final outcome = await _notifier.submit(
      title: _titleController.text,
      address: _addressController.text,
      notes: _notesController.text,
      materialsNeeded: _materialsController.text,
    );
    if (!mounted) return;
    switch (outcome) {
      case AddEventInvalid():
        return;
      case AddEventBusyEmployees(
        :final busyEmployees,
        :final start,
        :final end,
      ):
        final confirmed = await showBusyConflictDialog(
          context,
          busyEmployees: busyEmployees,
          start: start,
          end: end,
        );
        if (!confirmed || !mounted) return;
        final retry = await _notifier.submit(
          title: _titleController.text,
          address: _addressController.text,
          notes: _notesController.text,
          materialsNeeded: _materialsController.text,
          forceBusy: true,
        );
        if (!mounted) return;
        if (retry is AddEventSubmitted) {
          Navigator.pop(context, retry.appointment);
        } else if (retry is AddEventFailed) {
          _showFailedSnack();
        }
      case AddEventSubmitted(:final appointment):
        Navigator.pop(context, appointment);
      case AddEventFailed():
        _showFailedSnack();
    }
  }

  void _showFailedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.somethingWentWrongCreatingTheAppointment),
      ),
    );
  }

  String _errorText(AppointmentFormError key) {
    return switch (key) {
      AppointmentFormError.titleRequired => context.l10n.titleIsRequired,
      AppointmentFormError.dateRequired => context.l10n.pleaseSelectADate,
      AppointmentFormError.startTimeRequired =>
        context.l10n.pleaseSelectAStartTime,
      AppointmentFormError.endTimeRequired =>
        context.l10n.pleaseSelectAnEndTime,
      AppointmentFormError.endTimeMustBeAfterStart =>
        context.l10n.mustBeAfterStartTime,
      AppointmentFormError.clientRequired => context.l10n.pleaseSelectAClient,
      AppointmentFormError.employeesRequired =>
        context.l10n.pleaseSelectAtLeastOneEmployee,
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
              sheetContext.l10n.newAppointment,
              style: Theme.of(sheetContext).textTheme.headlineLarge,
            ),
            const SizedBox(height: AppSpacing.sp16),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sp16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: sheetContext.l10n.serviceTitle,
                hint: sheetContext.l10n.eGPlumbingRepair,
                controller: _titleController,
                required: true,
                errorText: _errorFor(state.errors, 'title'),
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),
            formLabel(sheetContext, sheetContext.l10n.client, required: true),
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
              sheetContext.l10n.assignEmployee,
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
                label: sheetContext.l10n.date,
                hint: sheetContext.l10n.selectDate,
                controller: _dateController,
                required: true,
                readOnly: true,
                suffixIcon:
                    const Icon(Icons.calendar_today_outlined, size: 18),
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
                      label: sheetContext.l10n.startTime,
                      hint: sheetContext.l10n.start,
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
                      label: sheetContext.l10n.endTime,
                      hint: sheetContext.l10n.end,
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
                label: sheetContext.l10n.materialsNeeded,
                hint: sheetContext.l10n.typeTheMaterialsHere,
                controller: _materialsController,
                optional: true,
                maxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: sheetContext.l10n.notes,
                hint: sheetContext.l10n.typeTheNoteHere,
                controller: _notesController,
                optional: true,
                maxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),
            formLabel(sheetContext, sheetContext.l10n.pictures, optional: true),
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
                  : Text(sheetContext.l10n.saveAppointment),
            ),
          ],
        );
      },
    );
  }
}

