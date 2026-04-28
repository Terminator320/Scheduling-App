import 'dart:io';

import 'package:flutter/material.dart';

import 'package:scheduling/core/services/image_compress_service.dart';
import 'package:scheduling/core/services/image_picker_service.dart';
import 'package:scheduling/core/services/image_storage_service.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/models/appointment_image.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/cupertino_time_picker.dart';
import 'package:scheduling/features/calendar/widgets/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/time_range_row.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

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

  final _formKey = GlobalKey<FormState>();

  final _compressService = ImageCompressService();
  final _storageService = ImageStorageService();
  final _imageService = ImagePickerService();
  final _userService = UserService();



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
    _notesController = TextEditingController(text: a.notes);
    _materialsController = TextEditingController(text: a.materialsNeeded);

    _selectedDate = a.startTime;
    _selectedStartTime = TimeOfDay.fromDateTime(a.startTime);
    _selectedEndTime = TimeOfDay.fromDateTime(a.endTime);
    _existingImages = List.from(a.pictures);

    _loadEmployees();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _dateController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _notesController.dispose();
    _materialsController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    _userService.employeesStream().listen((employees) {
      if (!mounted) return;
      setState(() {
        _allEmployees = employees;
        _selectedEmployees = employees
            .where((e) => widget.appointment.employeeIds.contains(e.id))
            .toList();
      });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Something went wrong")),
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
          ? "Title is required"
          : null;
      _errors['date'] = _dateController.text.trim().isEmpty
          ? "Please select a date"
          : null;
      _errors['startTime'] = _startTimeController.text.trim().isEmpty
          ? "Please select a start time"
          : null;
      _errors['endTime'] = _endTimeController.text.trim().isEmpty
          ? "Please select an end time"
          : (() {
              final start =
                  _selectedStartTime.hour * 60 + _selectedStartTime.minute;
              final end = _selectedEndTime.hour * 60 + _selectedEndTime.minute;
              return end <= start ? "Must be after start time" : null;
            })();
      _errors['employees'] = _selectedEmployees.isEmpty
          ? "Please select at least one employee"
          : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    if (_selectedEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one employee")),
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

      List<AppointmentImage> uploadedImages = const [];
      if (_newImages.isNotEmpty) {
        final compressed = await _compressService.compressImages(_newImages);
        uploadedImages =
            await _storageService.uploadImages(appointmentId, compressed);
      }
      final allPictures = [..._existingImages, ...uploadedImages];

      final updated = AppointmentRecord(
        id: widget.appointment.id,
        title: _titleController.text.trim(),
        startTime: startTime,
        endTime: endTime,
        clientId: widget.appointment.clientId,
        clientName: widget.appointment.clientName,
        clientPhone: widget.appointment.clientPhone,
        address: widget.appointment.address,
        employeeIds: _selectedEmployees.map((e) => e.id).toList(),
        employeeNames: _selectedEmployees.map((e) => e.name).toList(),
        notes: _notesController.text.trim(),
        materialsNeeded: _materialsController.text.trim(),
        pictures: allPictures,
        status: widget.appointment.status,
      );

      await AppointmentService().updateAppointment(updated);

      if (_removedExistingImages.isNotEmpty) {
        await _storageService.deleteImages(List.of(_removedExistingImages));
        _removedExistingImages.clear();
      }

      if (mounted) setState(() => _isEditing = false);
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Something went wrong saving changes")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.95;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: 16),
                _isEditing ? _buildEditHeader() : _buildViewHeader(),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),
                if (_isEditing)
                  ..._buildEditFields()
                else
                  ..._buildViewFields(),
                const SizedBox(height: 20),
                _buildPhotosSection(),
                const SizedBox(height: 20),
                _buildEmployeesSection(),
                if (widget.showActions) ...[
                  const SizedBox(height: 24),
                  _buildActionButtons(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── view header ───────────────────────────────────────────────

  Widget _buildViewHeader() {
    final a = widget.appointment;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Column(
      children: [
        Text(
          a.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 13,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(DateUtilsHelper.formatDate(a.startTime), style: secondaryStyle),
            const SizedBox(width: 12),
            Icon(
              Icons.access_time_outlined,
              size: 13,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              "${DateUtilsHelper.formatTime(a.startTime)} – ${DateUtilsHelper.formatTime(a.endTime)}",
              style: secondaryStyle,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditHeader() {
    return Text(
      "Edit job",
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineLarge,
    );
  }

  List<Widget> _buildViewFields() {
    final a = widget.appointment;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          formSectionLabel(context, "Client"),
          const SizedBox(height: 6),
          Text(
            a.clientName,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          Text(
            a.clientPhone.isNotEmpty ? a.clientPhone : "No number",
            style: theme.textTheme.bodySmall?.copyWith(
              color: a.clientPhone.isNotEmpty ? null : muted,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _viewSection("Address", a.address.isNotEmpty ? a.address : "No address"),
      const SizedBox(height: 16),
      _viewSection("Notes", a.notes.isNotEmpty ? a.notes : "No notes"),
      const SizedBox(height: 16),
      formSectionLabel(context, "Materials needed"),
      const SizedBox(height: 8),
      a.materialsNeeded.isNotEmpty
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
          : Text(
              "No materials",
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
    ];
  }

  Widget _viewSection(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formSectionLabel(context, label),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      ],
    );
  }

  List<Widget> _buildEditFields() {
    return [
      LabeledTextField(
        label: "Job title",
        hint: "e.g. Plumbing repair",
        controller: _titleController,
        errorText: _errors['title'],
        onChanged: (_) {
          if (_errors['title'] != null) {
            setState(() => _errors['title'] = null);
          }
        },
      ),
      const SizedBox(height: 16),

      LabeledTextField(
        label: "Date",
        hint: "Select date",
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
      const SizedBox(height: 16),

      formLabel(context, "Time"),
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
      const SizedBox(height: 16),

      LabeledTextField(
        label: "Notes",
        hint: "Type the note here...",
        controller: _notesController,
        optional: true,
        maxLines: 3,
      ),
      const SizedBox(height: 16),

      LabeledTextField(
        label: "Materials needed",
        hint: "e.g. Pipe wrench, tape (comma separated)",
        controller: _materialsController,
        optional: true,
      ),
    ];
  }

  // Photos Section
  Widget _buildPhotosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formSectionLabel(context, "Photos"),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formSectionLabel(context, "Employees"),
        const SizedBox(height: 8),
        EmployeePicker(
          allEmployees: _allEmployees,
          selectedEmployees: _selectedEmployees,
          selectable: _isEditing,
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  // Button switching
  Widget _buildActionButtons() {
    final now = DateTime.now();
    final isToday = widget.appointment.startTime.year == now.year &&
        widget.appointment.startTime.month == now.month &&
        widget.appointment.startTime.day == now.day;
    final scheme = Theme.of(context).colorScheme;
    final isDone = widget.appointment.status == 'done';

    // Mode édition — inchangé
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isSaving ? null : _cancelEdit,
              child: const Text("Cancel"),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
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
                ),
              )
                  : const Text("Save changes"),
            ),
          ),
        ],
      );
    }

    // Mode lecture — boutons selon le contexte
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bouton Done uniquement si c'est aujourd'hui et pas déjà "done"
        if (isToday && !isDone)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _isSaving ? null : _markAsDone,  // ← appel correct
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
            label: const Text("Mark as done"),
          ),

        // Déjà complété
        if (isDone)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green),
            ),
            onPressed: null, // désactivé
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text("Completed"),
          ),
      ],
    );
  }
}
