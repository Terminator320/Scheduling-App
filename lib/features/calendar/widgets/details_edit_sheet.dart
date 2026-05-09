import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/services/image_picker_service.dart';
import 'package:scheduling/core/services/image_storage_service.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/models/appointment_image.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/cupertino_time_picker.dart';
import 'package:scheduling/features/calendar/widgets/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/time_range_row.dart';
import 'package:scheduling/features/clients/models/client_record.dart';
import 'package:scheduling/features/clients/services/client_service.dart';
import 'package:scheduling/features/clients/widgets/client_search_field.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';



class EventDetailsSheet extends StatefulWidget {
  final AppointmentRecord appointment;
  final bool showActions;
  final bool initialEditing;

  const EventDetailsSheet({
    super.key,
    required this.appointment,
    this.showActions = true,
    this.initialEditing = false,
  });

  @override
  State<EventDetailsSheet> createState() => _EventDetailsSheetState();
}

class _EventDetailsSheetState extends State<EventDetailsSheet> {
  bool _isEditing = false;
  final Map<String, String?> _errors = {};

  // controllers
  late final TextEditingController _titleController;
  late final TextEditingController _dateController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;
  late final TextEditingController _clientSearchController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  late final TextEditingController _materialsController;

  // state
  late DateTime _selectedDate;
  late TimeOfDay _selectedStartTime;
  late TimeOfDay _selectedEndTime;

  List<EmployeeRecord> _allEmployees = [];
  List<EmployeeRecord> _selectedEmployees = [];
  List<AppointmentImage> _existingImages = [];
  final List<AppointmentImage> _removedExistingImages = [];
  List<File> _newImages = [];
  bool _isSaving = false;
  ClientRecord? _client;
  StreamSubscription? _employeesSub;
  ClientRecord? _selectedClient;
  List<ClientRecord> _clientResults = [];
  bool _isSearchingClient = false;

  final _imageUploadService = AppointmentImageUploadService();
  final _storageService = ImageStorageService();
  final _imageService = ImagePickerService();
  final _userService = UserService();
  final _clientService = ClientService();

  @override
  void initState() {
    super.initState();
    _isEditing = widget.initialEditing;
    final a = widget.appointment;

    _titleController = TextEditingController(text: a.title);
    _dateController = TextEditingController(
      text: DateUtilsHelper.formatDate(a.startTime),
    );
    _startTimeController = TextEditingController(
      text: DateUtilsHelper.formatTime(a.startTime),
    );
    _endTimeController = TextEditingController(
      text: DateUtilsHelper.formatTime(a.endTime),
    );
    _clientSearchController = TextEditingController(text: a.clientName);
    _addressController = TextEditingController(text: a.address);
    _notesController = TextEditingController(text: a.notes);
    _materialsController = TextEditingController(text: a.materialsNeeded);

    _selectedDate = a.startTime;
    _selectedStartTime = TimeOfDay.fromDateTime(a.startTime);
    _selectedEndTime = TimeOfDay.fromDateTime(a.endTime);
    _existingImages = List.from(a.pictures);

    _loadEmployees();
    _loadClient();
  }

  @override
  void dispose() {
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

  Future<void> _loadEmployees() async {
    _employeesSub = _userService.employeesStream().listen((employees) {
      if (!mounted) return;
      setState(() {
        _allEmployees = employees;
        _selectedEmployees = employees
            .where((e) => widget.appointment.employeeIds.contains(e.id))
            .toList();
      });
    });
  }

  Future<void> _loadClient() async {
    final clientId = widget.appointment.clientId.trim();
    if (clientId.isEmpty) return;

    try {
      final client = await _clientService.getClientById(clientId);
      if (!mounted) return;
      setState(() {
        _client = client;
        _selectedClient = client;
      });
    } catch (_) {
      // Keep the appointment details usable even if the client record cannot load.
    }
  }

  Future<void> _searchClients(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _clientResults = [];
        _isSearchingClient = false;
      });
      return;
    }
    setState(() => _isSearchingClient = true);
    try {
      final results = await _clientService.searchClients(query);
      if (!mounted) return;
      setState(() {
        _clientResults = results;
        _isSearchingClient = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isSearchingClient = false);
    }
  }

  void _selectClient(ClientRecord client) {
    setState(() {
      _selectedClient = client;
      _client = client;
      _clientSearchController.text = client.displayName;
      _addressController.text = client.address;
      _clientResults = [];
      _errors['client'] = null;
    });
  }

  void _clearClient() {
    setState(() {
      _selectedClient = null;
      _client = null;
      _clientSearchController.clear();
      _addressController.clear();
      _clientResults = [];
    });
  }

  Future<void> _markAsDone() async {
    final id = widget.appointment.id;
    if (id == null) return;

    setState(() => _isSaving = true);
    try {
      await AppointmentService().updateAppointmentStatus(
        appointmentId: id,
        status: 'done',
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text(context.l10n.somethingWentWrong)),
        );
      }
    }
  }

  Future<void> _cancelAppointment() async {
    final id = widget.appointment.id;
    if (id == null) return;
    setState(() => _isSaving = true);
    try {
      await AppointmentService().updateAppointmentStatus(
        appointmentId: id,
        status: 'cancelled',
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.somethingWentWrong)),
        );
      }
    }
  }

  void _cancelEdit() {
    final a = widget.appointment;
    setState(() {
      _isEditing = false;
      _titleController.text = a.title;
      _dateController.text = DateUtilsHelper.formatDate(a.startTime);
      _startTimeController.text = DateUtilsHelper.formatTime(a.startTime);
      _endTimeController.text = DateUtilsHelper.formatTime(a.endTime);
      _clientSearchController.text = _client?.displayName ?? a.clientName;
      _selectedClient = _client;
      _addressController.text = a.address;
      _notesController.text = a.notes;
      _materialsController.text = a.materialsNeeded;
      _selectedDate = a.startTime;
      _selectedStartTime = TimeOfDay.fromDateTime(a.startTime);
      _selectedEndTime = TimeOfDay.fromDateTime(a.endTime);
      _existingImages = List.from(a.pictures);
      _removedExistingImages.clear();
      _newImages = [];
      _selectedEmployees = _allEmployees
          .where((e) => a.employeeIds.contains(e.id))
          .toList();
    });
  }

  Future<void> _save() async {
    setState(() {
      _errors['title'] = _titleController.text.trim().isEmpty
          ? context.l10n.titleIsRequired
          : null;
      _errors['date'] = _dateController.text.trim().isEmpty
          ? context.l10n.pleaseSelectADate
          : null;
      _errors['startTime'] = _startTimeController.text.trim().isEmpty
          ? context.l10n.pleaseSelectAStartTime
          : null;
      _errors['endTime'] = _endTimeController.text.trim().isEmpty
          ? context.l10n.pleaseSelectAnEndTime
          : (() {
              final start =
                  _selectedStartTime.hour * 60 + _selectedStartTime.minute;
              final end = _selectedEndTime.hour * 60 + _selectedEndTime.minute;
              return end <= start ? context.l10n.mustBeAfterStartTime : null;
            })();
      _errors['client'] =
          _selectedClient == null &&
              widget.appointment.clientId.trim().isEmpty
          ? context.l10n.pleaseSelectAClient
          : null;
      _errors['employees'] = _selectedEmployees.isEmpty
          ? context.l10n.pleaseSelectAtLeastOneEmployee
          : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    if (_selectedEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.pleaseSelectAtLeastOneEmployee),
        ),
      );
      return;
    }

    final startTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedStartTime.hour,
      _selectedStartTime.minute,
    );
    final endTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedEndTime.hour,
      _selectedEndTime.minute,
    );

    setState(() => _isSaving = true);

    try {
      final appointmentId = widget.appointment.id;
      if (appointmentId == null) {
        throw StateError('Cannot save an appointment without an id.');
      }

      // 1. Delete removed images from Storage before saving so that orphaned
      //    files can never accumulate. Errors surface here instead of silently
      //    failing in the background.
      if (_removedExistingImages.isNotEmpty) {
        await _storageService.deleteImages(_removedExistingImages);
      }

      // 2. Save the appointment with the updated pictures list.
      final updated = AppointmentRecord(
        id: widget.appointment.id,
        title: _titleController.text.trim(),
        startTime: startTime,
        endTime: endTime,
        clientId: _selectedClient?.id ?? widget.appointment.clientId,
        clientName: _selectedClient?.displayName ??
            (_clientSearchController.text.trim().isNotEmpty
                ? _clientSearchController.text.trim()
                : widget.appointment.clientName),
        clientPhone: _selectedClient?.phone ?? widget.appointment.clientPhone,
        address: _addressController.text.trim(),
        employeeIds: _selectedEmployees.map((e) => e.id).toList(),
        employeeNames: _selectedEmployees.map((e) => e.name).toList(),
        notes: _notesController.text.trim(),
        materialsNeeded: _materialsController.text.trim(),
        pictures: _existingImages,
        status: widget.appointment.status,
      );

      await AppointmentService().updateAppointment(updated);

      if (mounted) setState(() => _isEditing = false);
      if (mounted) Navigator.pop(context, updated);

      // 3. Upload new images in the background — sheet is already closed.
      if (_newImages.isNotEmpty) {
        _imageUploadService.uploadInBackground(
          appointmentId: appointmentId,
          newImages: _newImages,
          existingImages: _existingImages,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.somethingWentWrongSavingChanges),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            _isEditing ? _buildEditHeader() : _buildViewHeader(),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
            if (_isEditing) ..._buildEditFields() else ..._buildViewFields(),
            const SizedBox(height: 20),
            _buildPhotosSection(),
            const SizedBox(height: 20),
            _buildEmployeesSection(),
            if (widget.showActions) ...[
              const SizedBox(height: 24),
              _buildActionButtons(),
            ],
          ],
        );
      },
    );
  }

  // ── view header ───────────────────────────────────────────────

  AppointmentStatus _appointmentStatus() => switch (widget.appointment.status.toLowerCase()) {
    'done' || 'completed' => AppointmentStatus.done,
    'cancelled' => AppointmentStatus.cancelled,
    'pending' => AppointmentStatus.pending,
    _ => AppointmentStatus.confirmed,
  };

  Widget _buildViewHeader() {
    final a = widget.appointment;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(a.title, style: theme.textTheme.headlineLarge),
            ),
            const SizedBox(width: 8),
            StatusChip(status: _appointmentStatus()),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 13, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              DateUtilsHelper.formatDate(a.startTime),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Icon(Icons.access_time_outlined, size: 13, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              '${DateUtilsHelper.formatTime(a.startTime)} – ${DateUtilsHelper.formatTime(a.endTime)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditHeader() {
    return Text(
      context.l10n.editJob,
      style: Theme.of(context).textTheme.headlineLarge,
    );
  }

  List<Widget> _buildViewFields() {
    final a = widget.appointment;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    return [
      _ViewRow(
        icon: Icons.person_outline,
        label: context.l10n.client,
        value: _client?.displayName ?? a.clientName,
        subtitle: a.clientPhone.isNotEmpty ? a.clientPhone : context.l10n.noNumber,
      ),
      if ((_client?.contacts ?? const <ClientContact>[]).isNotEmpty) ...[
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.contacts,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted)),
              const SizedBox(height: 8),
              ..._client!.contacts.map(_contactCard),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      _ViewRow(
        icon: Icons.location_on_outlined,
        label: context.l10n.address,
        value: a.address.isNotEmpty ? a.address : context.l10n.noAddress,
        onTap: a.address.isNotEmpty
            ? () => AddressMapLauncher.showMapChoices(context, address: a.address)
            : null,
      ),
      const SizedBox(height: 16),
      _ViewRow(
        icon: Icons.notes_outlined,
        label: context.l10n.notes,
        value: a.notes.isNotEmpty ? a.notes : context.l10n.noNotes,
      ),
      const SizedBox(height: 16),
      _ViewRow(
        icon: Icons.build_outlined,
        label: context.l10n.materialsNeeded,
        value: a.materialsNeeded.isEmpty ? context.l10n.noMaterials : '',
        customValue: a.materialsNeeded.isNotEmpty
            ? Wrap(
                spacing: 6,
                runSpacing: 6,
                children: a.materialsNeeded
                    .split(',')
                    .map((m) => m.trim())
                    .where((m) => m.isNotEmpty)
                    .map(
                      (m) => Chip(
                        label: Text(m, style: theme.textTheme.bodySmall),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              )
            : null,
      ),
    ];
  }

  Widget _contactCard(ClientContact contact) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (contact.name.trim().isNotEmpty)
            _contactLine(Icons.person_outline, contact.name.trim()),
          if (contact.phone.trim().isNotEmpty)
            _contactLine(Icons.phone_outlined, contact.phone.trim()),
          if (contact.email.trim().isNotEmpty)
            _contactLine(Icons.mail_outline, contact.email.trim()),
        ],
      ),
    );
  }

  Widget _contactLine(IconData icon, String text) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEditFields() {
    return [
      SheetFocusScroll(
        child: LabeledTextField(
          label: context.l10n.jobTitle2,
          hint: context.l10n.eGPlumbingRepair,
          controller: _titleController,
          errorText: _errors['title'],
          onChanged: (_) {
            if (_errors['title'] != null) {
              setState(() => _errors['title'] = null);
            }
          },
        ),
      ),
      const SizedBox(height: 16),

      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.date,
                hint: context.l10n.selectDate,
                controller: _dateController,
                readOnly: true,
                errorText: _errors['date'],
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null) return;
                  setState(() {
                    _selectedDate = picked;
                    _dateController.text = DateUtilsHelper.formatDate(picked);
                    _errors['date'] = null;
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                formLabel(context, context.l10n.time),
                TimeRangeRow(
                  startController: _startTimeController,
                  endController: _endTimeController,
                  selectedStart: _selectedStartTime,
                  selectedEnd: _selectedEndTime,
                  onTapStart: () async {
                    final picked = await showCupertinoTimePicker(
                      context,
                      initialTime: _selectedStartTime,
                    );
                    if (picked == null) return;
                    setState(() {
                      _selectedStartTime = picked;
                      _startTimeController.text = picked.format(context);
                      _errors['startTime'] = null;
                    });
                  },
                  onTapEnd: () async {
                    final picked = await showCupertinoTimePicker(
                      context,
                      initialTime: _selectedEndTime,
                    );
                    if (picked == null) return;
                    setState(() {
                      _selectedEndTime = picked;
                      _endTimeController.text = picked.format(context);
                      _errors['endTime'] = null;
                    });
                  },
                  startError: _errors['startTime'],
                  endError: _errors['endTime'],
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      formLabel(context, context.l10n.client),
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
      const SizedBox(height: 16),

      SheetFocusScroll(
        child: AddressAutocompleteField(
          controller: _addressController,
          optional: true,
        ),
      ),
      const SizedBox(height: 16),

      SheetFocusScroll(
        child: LabeledTextField(
          label: context.l10n.notes,
          hint: context.l10n.typeTheNoteHere,
          controller: _notesController,
          optional: true,
          maxLines: 3,
        ),
      ),
      const SizedBox(height: 16),

      SheetFocusScroll(
        child: LabeledTextField(
          label: context.l10n.materialsNeeded,
          hint: context.l10n.eGPipeWrenchTapeCommaSeparated,
          controller: _materialsController,
          optional: true,
        ),
      ),
    ];
  }

  // Photos Section
  Widget _buildPhotosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formSectionLabel(context, context.l10n.pictures),
        const SizedBox(height: 8),
        PhotoPickerSection(
          existingImages: _existingImages,
          newImages: _newImages,
          isEditing: _isEditing,
          onPickImages: () async {
            final images = await _imageService.pickMultiImages();
            if (images.isNotEmpty) setState(() => _newImages.addAll(images));
          },
          onRemoveExisting: (i) => setState(() {
            _removedExistingImages.add(_existingImages[i]);
            _existingImages.removeAt(i);
          }),
          onRemoveNew: (i) => setState(() => _newImages.removeAt(i)),
        ),
      ],
    );
  }

  // Employee Section
  Widget _buildEmployeesSection() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formSectionLabel(context, context.l10n.employees),
        const SizedBox(height: 8),
        if (!_isEditing) ...[
          ..._selectedEmployees.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(e.name, style: theme.textTheme.bodyMedium),
              ],
            ),
          )),
        ] else ...[
          EmployeePicker(
            allEmployees: _allEmployees,
            selectedEmployees: _selectedEmployees,
            selectable: true,
            hasError: _errors['employees'] != null,
            onToggle: (employee) => setState(() {
              if (_selectedEmployees.any((e) => e.id == employee.id)) {
                _selectedEmployees.removeWhere((e) => e.id == employee.id);
              } else {
                _selectedEmployees.add(employee);
                _errors['employees'] = null;
              }
            }),
          ),
          if (_errors['employees'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(
                _errors['employees']!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ),
        ],
      ],
    );
  }

  // Button switching
  Widget _buildActionButtons() {
    final now = DateTime.now();
    final isToday =
        widget.appointment.startTime.year == now.year &&
        widget.appointment.startTime.month == now.month &&
        widget.appointment.startTime.day == now.day;
    final scheme = Theme.of(context).colorScheme;
    final isDone = widget.appointment.status == 'done';

    if (_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _isSaving ? null : _cancelEdit,
            child: Text(context.l10n.cancel),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    )
                  )
                : Text(context.l10n.saveChanges),
          ),
        ],
      );
    }

    // View mode — Edit + Cancel buttons side-by-side, then status action
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isSaving ? null : () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(context.l10n.editJob),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _cancelAppointment,
                icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                label: Text(
                  context.l10n.cancel,
                  style: const TextStyle(color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
          ],
        ),

        if (isToday && !isDone) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.green,
            ),
            onPressed: _isSaving ? null : _markAsDone,
            icon: _isSaving
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(context.l10n.markAsDone),
          ),
        ],

        if (isDone) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green),
            ),
            onPressed: null,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(context.l10n.completed),
          ),
        ],
      ],
    );
  }
}

class _ViewRow extends StatelessWidget {
  const _ViewRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.customValue,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Widget? customValue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Widget valueWidget;
    if (onTap != null && customValue == null) {
      final colored = Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.5,
          color: Color.lerp(scheme.primary, const Color(0xFF4A8DFF), 0.5),
        ),
      );
      valueWidget = InkWell(
        borderRadius: BorderRadius.circular(AppRadius.r8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: colored),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new, size: 16),
            ],
          ),
        ),
      );
    } else {
      valueWidget = customValue ??
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 12),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              valueWidget,
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
