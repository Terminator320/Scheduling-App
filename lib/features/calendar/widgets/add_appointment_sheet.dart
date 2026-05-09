import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:scheduling/core/services/image_picker_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/appointment_draft_defaults.dart';
import 'package:scheduling/features/calendar/utils/cupertino_time_picker.dart';
import 'package:scheduling/features/calendar/widgets/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/photo_picker_section.dart';
import 'package:scheduling/features/clients/models/client_record.dart';
import 'package:scheduling/features/clients/services/client_service.dart';
import 'package:scheduling/features/clients/widgets/client_search_field.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

class AddEventSheet extends StatefulWidget {
  const AddEventSheet({
    super.key,
    this.initialDate,
    this.employeesStream,
  });

  final DateTime? initialDate;
  final Stream<List<EmployeeRecord>>? employeesStream;

  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  final Map<String, String?> _errors = {};

  final _titleController = TextEditingController();
  final _dateController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _clientSearchController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final _materialsController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;
  bool _endTimeWasPickedManually = false;

  ClientRecord? _selectedClient;
  List<ClientRecord> _clientResults = [];
  bool _isSearchingClient = false;
  bool _useCustomAddress = false;

  List<EmployeeRecord> _allEmployees = [];
  final List<EmployeeRecord> _selectedEmployees = [];

  final List<File> _selectedImages = [];
  bool _isSubmitting = false;
  StreamSubscription? _employeesSub;
  Timer? _clientSearchDebounce;
  final _imageService = ImagePickerService();
  final _imageUploadService = AppointmentImageUploadService();
  final _clientService = ClientService();
  final _userService = UserService();
  final _appointmentService = AppointmentService();

  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialDate;
    if (initialDate != null) {
      _selectedDate = initialDate;
      _dateController.text = DateUtilsHelper.formatDate(initialDate);
    }
    _initStreams();
  }

  void _initStreams() {
    _employeesSub = (widget.employeesStream ?? _userService.employeesStream()).listen((employees) {
      if (mounted) setState(() => _allEmployees = employees);
    });
  }

  @override
  void dispose() {
    _clientSearchDebounce?.cancel();
    _employeesSub?.cancel();
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

  Future<void> _searchClients(String query) async {
    _clientSearchDebounce?.cancel();
    if (!ClientSearchPolicy.shouldSearch(query)) {
      setState(() {
        _clientResults = [];
        _isSearchingClient = false;
      });
      return;
    }
    setState(() => _isSearchingClient = true);
    _clientSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await _clientService.searchClients(query);
        if (mounted) {
          setState(() {
            _clientResults = results;
            _isSearchingClient = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingClient = false);
      }
    });
  }

  void _selectClient(ClientRecord client) {
    setState(() {
      _selectedClient = client;
      _clientSearchController.text = client.displayName;
      _addressController.text = client.address;
      _clientResults = [];
      _useCustomAddress = false;
      _errors['client'] = null;
    });
  }

  void _clearClient() {
    setState(() {
      _selectedClient = null;
      _clientSearchController.clear();
      _addressController.clear();
      _clientResults = [];
      _useCustomAddress = false;
    });
  }

  void _toggleEmployee(EmployeeRecord employee) {
    setState(() {
      if (_selectedEmployees.any((e) => e.id == employee.id)) {
        _selectedEmployees.removeWhere((e) => e.id == employee.id);
      } else {
        _selectedEmployees.add(employee);
        _errors['employees'] = null;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
      _dateController.text = DateUtilsHelper.formatDate(picked);
      _errors['date'] = null;
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showCupertinoTimePicker(
      context,
      initialTime: _selectedStartTime,
    );
    if (picked == null) return;
    setState(() {
      _selectedStartTime = picked;
      _startTimeController.text = picked.format(context);
      _errors['startTime'] = null;
      if (!_endTimeWasPickedManually) {
        final defaultEndTime = AppointmentDraftDefaults.defaultEndTime(picked);
        _selectedEndTime = defaultEndTime;
        _endTimeController.text = defaultEndTime.format(context);
        _errors['endTime'] = null;
      }
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showCupertinoTimePicker(
      context,
      initialTime: _selectedEndTime,
    );
    if (picked == null) return;
    setState(() {
      _endTimeWasPickedManually = true;
      _selectedEndTime = picked;
      _endTimeController.text = picked.format(context);
      _errors['endTime'] = null;
    });
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime _combineEndDateAndTime(DateTime date, TimeOfDay time) {
    final endTime = _combineDateAndTime(date, time);
    if (_selectedStartTime == null) return endTime;

    final startTime = _combineDateAndTime(date, _selectedStartTime!);
    return endTime.isAfter(startTime)
        ? endTime
        : endTime.add(const Duration(days: 1));
  }

  void _showSnack(BuildContext ctx, String message) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _submit(BuildContext ctx) async {
    setState(() {
      final hasValidTimeRange =
          _selectedDate == null ||
          _selectedStartTime == null ||
          _selectedEndTime == null ||
          _combineEndDateAndTime(
            _selectedDate!,
            _selectedEndTime!,
          ).isAfter(_combineDateAndTime(_selectedDate!, _selectedStartTime!));
      _errors['title'] = _titleController.text.trim().isEmpty
          ? context.l10n.titleIsRequired
          : null;
      _errors['date'] = _selectedDate == null
          ? context.l10n.pleaseSelectADate
          : null;
      _errors['startTime'] = _selectedStartTime == null
          ? context.l10n.pleaseSelectAStartTime
          : null;
      _errors['endTime'] = _selectedEndTime == null
          ? context.l10n.pleaseSelectAnEndTime
          : !hasValidTimeRange
          ? context.l10n.mustBeAfterStartTime
          : null;
      _errors['client'] = _selectedClient == null
          ? context.l10n.pleaseSelectAClient
          : null;
      _errors['employees'] = _selectedEmployees.isEmpty
          ? context.l10n.pleaseSelectAtLeastOneEmployee
          : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    final startTime = _combineDateAndTime(_selectedDate!, _selectedStartTime!);
    final endTime = _combineDateAndTime(_selectedDate!, _selectedEndTime!);

    final busyEmployees = await _appointmentService.checkAvailableEmployee(
      employeeId: _selectedEmployees,
      start: startTime,
      end: endTime,
    );

    if (busyEmployees.isNotEmpty) {
      setState(
        () => _errors['employees'] =
            '${context.l10n.busy}: ${busyEmployees.map((e) => e.name).join(', ')}',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final docRef = _appointmentService.newDocRef();
      final start = _combineDateAndTime(_selectedDate!, _selectedStartTime!);
      final end = _combineEndDateAndTime(_selectedDate!, _selectedEndTime!);

      final newAppointment = AppointmentRecord(
        id: docRef.id,
        title: _titleController.text.trim(),
        startTime: start,
        endTime: end,
        clientId: _selectedClient!.id,
        clientName: _selectedClient!.displayName,
        clientPhone: _selectedClient!.phone,
        address: _addressController.text.trim(),
        employeeIds: _selectedEmployees.map((e) => e.id).toList(),
        employeeNames: _selectedEmployees.map((e) => e.name).toList(),
        notes: _notesController.text.trim(),
        materialsNeeded: _materialsController.text.trim(),
        pictures: const [],
        status: 'booked',
      );

      await _appointmentService.addAppointment(newAppointment);

      if (ctx.mounted) Navigator.pop(ctx, newAppointment);

      if (_selectedImages.isNotEmpty) {
        _imageUploadService.uploadInBackground(
          appointmentId: docRef.id,
          newImages: _selectedImages,
        );
      }
    } catch (_) {
      if (ctx.mounted) {
        setState(() => _isSubmitting = false);
        _showSnack(ctx, ctx.l10n.somethingWentWrongCreatingTheAppointment);
      }
    }
  }

  Widget _buildAddressPill(BuildContext context) {
    final client = _selectedClient!;
    final address = client.address.isNotEmpty ? client.address : context.l10n.noAddress;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.r8),
            ),
            child: const Icon(Icons.location_on_outlined, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.clientSAddress,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _useCustomAddress = true),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              context.l10n.changeAddress,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressField(BuildContext context) {
    final showPill = _selectedClient != null && !_useCustomAddress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        if (showPill)
          _buildAddressPill(context)
        else ...[
          SheetFocusScroll(
            child: AddressAutocompleteField(
              controller: _addressController,

            ),
          ),
          if (_selectedClient != null && _useCustomAddress) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                _addressController.text = _selectedClient!.address;
                setState(() => _useCustomAddress = false);
              },
              child: Text(
                context.l10n.useClientsAddress,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: AppSpacing.sp16,
            right: AppSpacing.sp16,
            top: AppSpacing.sp12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.sp24,
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

            // Service / Title
            SheetFocusScroll(
              child: LabeledTextField(
                label: sheetContext.l10n.serviceTitle,
                hint: sheetContext.l10n.eGPlumbingRepair,
                controller: _titleController,
                required: true,
                errorText: _errors['title'],
                onChanged: (_) {
                  if (_errors['title'] != null) {
                    setState(() => _errors['title'] = null);
                  }
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),

            // Client
            formLabel(sheetContext, sheetContext.l10n.client, required: true),
            SheetFocusScroll(
              child: ClientSearchField(
                controller: _clientSearchController,
                selectedClient: _selectedClient,
                results: _clientResults,
                isSearching: _isSearchingClient,
                onChanged: _searchClients,
                onSelect: _selectClient,
                onClear: _clearClient,
                errorText: _errors['client'],
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),

            // Assign Employee
            formLabel(sheetContext, sheetContext.l10n.assignEmployee, required: true),
            const SizedBox(height: 6),
            EmployeePicker(
              allEmployees: _allEmployees,
              selectedEmployees: _selectedEmployees,
              onToggle: _toggleEmployee,
              hasError: _errors['employees'] != null,
            ),
            if (_errors['employees'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  _errors['employees']!,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sp16),

            // Date — full width
            SheetFocusScroll(
              child: LabeledTextField(
                label: sheetContext.l10n.date,
                hint: sheetContext.l10n.selectDate,
                controller: _dateController,
                required: true,
                readOnly: true,
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                errorText: _errors['date'],
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: AppSpacing.sp16),

            // Start time + End time side-by-side, each with their own label
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
                      errorText: _errors['startTime'],
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
                      errorText: _errors['endTime'],
                      onTap: _pickEndTime,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sp16),

            // Address (pill if client selected, field otherwise)
            _buildAddressField(sheetContext),
            const SizedBox(height: AppSpacing.sp16),

            // Materials needed
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

            // Notes
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

            // Photos
            formLabel(sheetContext, sheetContext.l10n.pictures, optional: true),
            PhotoPickerSection(
              existingImages: const [],
              newImages: _selectedImages,
              isEditing: true,
              onPickImages: () async {
                final images = await _imageService.pickMultiImages();
                if (images.isNotEmpty) {
                  setState(() => _selectedImages.addAll(images));
                }
              },
              onRemoveExisting: (_) {},
              onRemoveNew: (i) => setState(() => _selectedImages.removeAt(i)),
            ),
            const SizedBox(height: AppSpacing.sp24),

            // Save button
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _isSubmitting ? null : () => _submit(sheetContext),
              child: _isSubmitting
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
