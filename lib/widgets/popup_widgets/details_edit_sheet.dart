import 'dart:io';

import 'package:flutter/material.dart';
import '../../models/appointment_record.dart';
import '../../models/appointmentImage.dart';
import '../../models/employee_record.dart';
import '../../services/appointment_service.dart';
import '../../services/user_service.dart';
import '../../utils/date_utils_helper.dart';
import '../calendar_widgets/employee_picker.dart';
import '../../utils/calendar_utils/form_widgets.dart';
import '../../utils/images_utils/image_compress_service.dart';
import '../../utils/images_utils/image_picker_service.dart';
import '../../utils/images_utils/image_storage_service.dart';
import '../calendar_widgets/photo_picker_section.dart';
import '../calendar_widgets/time_range_row.dart';

class EventDetailsSheet extends StatefulWidget {
  final AppointmentRecord appointment;
  final bool showActions;

  const EventDetailsSheet({
    super.key,
    required this.appointment,
    this.showActions = true,
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
      _newImages = [];
      _selectedEmployees = _allEmployees
          .where((e) => a.employeeIds.contains(e.id))
          .toList();
    });
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job'),
        content: const Text('Are you sure you want to delete this job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final id = widget.appointment.id;
    if (id == null) return;
    await AppointmentService().deleteAppointment(id);
    if (!mounted) return;
    Navigator.pop(context, 'deleted');
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
      List<AppointmentImage> uploadedImages = const [];
      if (_newImages.isNotEmpty) {
        final compressed = await _compressService.compressImages(_newImages);
        uploadedImages = await _storageService.uploadImages(compressed);
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
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (sheetContext, scrollController) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(sheetContext).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 60,
              ),
              children: [
                _buildHandle(),
                _isEditing ? _buildEditHeader() : _buildViewHeader(),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                if (_isEditing)
                  ..._buildEditFields()
                else
                  ..._buildViewFields(),
                const SizedBox(height: 16),
                _buildPhotosSection(),
                const SizedBox(height: 16),
                _buildEmployeesSection(),
                if (widget.showActions) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  _buildActionButtons(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------- drag handle --------------
  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  // ── view header ───────────────────────────────────────────────

  Widget _buildViewHeader() {
    final a = widget.appointment;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          a.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 13,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              DateUtilsHelper.formatDate(a.startTime),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.access_time_outlined,
              size: 13,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              "${DateUtilsHelper.formatTime(a.startTime)} – ${DateUtilsHelper.formatTime(a.endTime)}",
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
      style: Theme.of(context).textTheme.titleLarge,
    );
  }

  List<Widget> _buildViewFields() {
    final a = widget.appointment;
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          formSectionLabel(context, "Client"),
          const SizedBox(height: 4),
          Text(
            a.clientName,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          Text(
            a.clientPhone.isNotEmpty ? a.clientPhone : "No number",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: a.clientPhone.isNotEmpty ? null : Colors.grey[500],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _viewSection("Address", a.address.isNotEmpty ? a.address : "No address"),
      const SizedBox(height: 14),
      _viewSection("Notes", a.notes.isNotEmpty ? a.notes : "No notes"),
      const SizedBox(height: 14),
      formSectionLabel(context, "Materials needed"),
      const SizedBox(height: 6),
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
                      label: Text(
                        m,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            )
          : Text(
              "No materials",
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
            ),
    ];
  }

  Widget _viewSection(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formSectionLabel(context, label),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      ],
    );
  }

  List<Widget> _buildEditFields() {
    return [
      formLabel(context, "Job title"),
      TextField(
        controller: _titleController,
        decoration: formInputDecoration(
          context,
          "e.g. Plumbing repair",
        ).copyWith(errorText: _errors['title']),
        onChanged: (_) => setState(() => _errors['title'] = null),
      ),
      const SizedBox(height: 14),

      formLabel(context, "Date"),
      TextField(
        controller: _dateController,
        readOnly: true,
        decoration: formInputDecoration(context, "Select date").copyWith(
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          errorText: _errors['date'],
        ),
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
      const SizedBox(height: 14),

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
      const SizedBox(height: 14),

      formLabel(context, "Notes", optional: true),
      TextField(
        controller: _notesController,
        decoration: formInputDecoration(context, "Type the note here..."),
        maxLines: 3,
      ),
      const SizedBox(height: 14),

      formLabel(context, "Materials needed", optional: true),
      TextField(
        controller: _materialsController,
        decoration: formInputDecoration(
          context,
          "e.g. Pipe wrench, tape (comma separated)",
        ),
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
          onRemoveExisting: (i) =>
              setState(() => _existingImages.removeAt(i)),
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
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isSaving ? null : _cancelEdit,
              child: const Text("Cancel"),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Save changes"),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _confirmDelete,
            child: const Text("Delete"),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => setState(() => _isEditing = true),
            child: const Text("Edit"),
          ),
        ),
      ],
    );
  }
}
