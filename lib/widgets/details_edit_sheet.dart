import 'dart:io';

import 'package:flutter/material.dart';
import '../models/appointment_record.dart';
import '../models/employee_record.dart';
import '../services/appointment_service.dart';
import '../services/user_service.dart';
import '../utils/date_utils_helper.dart';
import '../utils/employee_picker.dart';
import '../utils/images_utils/image_compress_service.dart';
import '../utils/images_utils/image_picker_service.dart';
import '../utils/images_utils/image_storage_service.dart';


class EventDetailsSheet extends StatefulWidget {
  final AppointmentRecord appointment;
  final bool showActions;
  final VoidCallback? onDelete;

  const EventDetailsSheet({
    super.key,
    required this.appointment,
    this.showActions = true,
    this.onDelete,
  });

  @override
  State<EventDetailsSheet> createState() => _EventDetailsSheetState();
}

class _EventDetailsSheetState extends State<EventDetailsSheet> {
  bool _isEditing = false;

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
  List<String> _existingPictureUrls = [];
  List<File> _newImages = [];

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
    _dateController =
        TextEditingController(text: DateUtilsHelper.formatDate(a.startTime));
    _startTimeController =
        TextEditingController(text: DateUtilsHelper.formatTime(a.startTime));
    _endTimeController =
        TextEditingController(text: DateUtilsHelper.formatTime(a.endTime));
    _notesController = TextEditingController(text: a.notes);
    _materialsController = TextEditingController(text: a.materialsNeeded);

    _selectedDate = a.startTime;
    _selectedStartTime = TimeOfDay.fromDateTime(a.startTime);
    _selectedEndTime = TimeOfDay.fromDateTime(a.endTime);
    _existingPictureUrls = List.from(a.pictures);

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
      _existingPictureUrls = List.from(a.pictures);
      _newImages = [];
      _selectedEmployees = _allEmployees
          .where((e) => a.employeeIds.contains(e.id))
          .toList();
    });
  }



  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one employee")),
      );
      return;
    }

    final startTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedStartTime.hour, _selectedStartTime.minute,
    );
    final endTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedEndTime.hour, _selectedEndTime.minute,
    );

    // TODO: upload _newImages and combine with _existingPictureUrls
    // final compressed = await _compressService.compressImages(_newImages);
    // final newUrls = await _storageService.uploadImages(compressed);
    // final allPictures = [..._existingPictureUrls, ...newUrls];

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
      pictures: _existingPictureUrls,
      // replace with allPictures when implemented
      status: widget.appointment.status,
    );

    await AppointmentService().updateAppointment(updated);
    if (mounted) setState(() => _isEditing = false);
  }


  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
              decoration: BoxDecoration(
                color: Theme
                    .of(context)
                    .colorScheme
                    .surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      left: MediaQuery.of(context).size.width * 0.05,
                      right: MediaQuery.of(context).size.width * 0.05,
                      top: 16,
                      bottom: MediaQuery
                          .of(context)
                          .viewInsets
                          .bottom + 24,
                    ),
                    children: [
                      _buildHandle(),
                      _isEditing ? _buildEditHeader() : _buildViewHeader(),
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      if (_isEditing) ..._buildEditFields
                        () else
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
                      ]

                    ],
                  )
              )
          );
        }
    );
  }


  // ── drag handle ──────────────────────────────────────────────
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
    return Column(
      children: [
        Text(
          a.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              DateUtilsHelper.formatDate(a.startTime),
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Icon(Icons.access_time_outlined,
                size: 13, color:Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              "${DateUtilsHelper.formatTime(a.startTime)} – "
                  "${DateUtilsHelper.formatTime(a.endTime)}",
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ],
    );
  }

  // ── edit header ───────────────────────────────────────────────
  Widget _buildEditHeader() {
    return const Text(
      "Edit job",
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
    );
  }

  // ── view fields ───────────────────────────────────────────────
  List<Widget> _buildViewFields() {
    final a = widget.appointment;
    return [
      _viewSection("Client", "${a.clientName}\n${a.clientPhone}"),
      const SizedBox(height: 14),
      _viewSection("Address",
          a.address.isNotEmpty ? a.address : "No address"),
      const SizedBox(height: 14),
      _viewSection("Notes",
          a.notes.isNotEmpty ? a.notes : "No notes"),
      const SizedBox(height: 14),
      _sectionLabel("Materials needed"),
      const SizedBox(height: 6),
      a.materialsNeeded.isNotEmpty
          ? Wrap(
        spacing: 6,
        runSpacing: 6,
        children: a.materialsNeeded
            .split(',')
            .map((m) => m.trim())
            .where((m) => m.isNotEmpty)
            .map((m) =>
            Chip(
              label: Text(m,
                  style: const TextStyle(fontSize: 12)),
              padding:
              const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ))
            .toList(),
      )
          : Text("No materials",
          style:
          TextStyle(fontSize: 14, color: Colors.grey[400])),
    ];
  }

  Widget _viewSection(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 14, height: 1.5)),
      ],
    );
  }

  // ── edit fields ───────────────────────────────────────────────
  List<Widget> _buildEditFields() {
    return [
      _label("Job title"),
      TextFormField(
        controller: _titleController,
        decoration: _inputDecoration("e.g. Plumbing repair"),
        validator: (v) =>
        v == null || v.isEmpty ? "Title is required" : null,
      ),
      const SizedBox(height: 14),

      _label("Date"),
      TextFormField(
        controller: _dateController,
        readOnly: true,
        decoration: _inputDecoration("Select date").copyWith(
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        validator: (v) =>
        v == null || v.isEmpty ? "Please select a date" : null,
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
          });
        },
      ),
      const SizedBox(height: 14),

      _label("Time"),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _startTimeController,
              readOnly: true,
              decoration: _inputDecoration("Start time").copyWith(
                suffixIcon: const Icon(Icons.access_time_outlined, size: 18),
              ),
              validator: (v) =>
              v == null || v.isEmpty ? "Required" : null,
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _selectedStartTime,
                );
                if (picked == null) return;
                setState(() {
                  _selectedStartTime = picked;
                  _startTimeController.text = picked.format(context);
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _endTimeController,
              readOnly: true,
              decoration: _inputDecoration("End time").copyWith(
                suffixIcon: const Icon(Icons.access_time_outlined, size: 18),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return "Required";
                final start = _selectedStartTime.hour * 60 +
                    _selectedStartTime.minute;
                final end =
                    _selectedEndTime.hour * 60 + _selectedEndTime.minute;
                if (end <= start) return "Must be after start";
                return null;
              },
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _selectedEndTime,
                );
                if (picked == null) return;
                setState(() {
                  _selectedEndTime = picked;
                  _endTimeController.text = picked.format(context);
                });
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),

      _label("Notes", optional: true),
      TextFormField(
        controller: _notesController,
        decoration: _inputDecoration("Type the note here..."),
        maxLines: 3,
      ),
      const SizedBox(height: 14),

      _label("Materials needed", optional: true),
      TextFormField(
        controller: _materialsController,
        decoration:
        _inputDecoration("e.g. Pipe wrench, tape (comma separated)"),
      ),
    ];
  }

  // ── photos section ────────────────────────────────────────────
  Widget _buildPhotosSection() {
    final hasPhotos =
        _existingPictureUrls.isNotEmpty || _newImages.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel("Photos"),
        const SizedBox(height: 8),
        if (hasPhotos)
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // existing network images
                ..._existingPictureUrls
                    .asMap()
                    .entries
                    .map((entry) {
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            entry.value,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (_isEditing)
                        Positioned(
                          top: 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() =>
                                    _existingPictureUrls.removeAt(entry.key)),
                            child: _removeButton(),
                          ),
                        ),
                    ],
                  );
                }),
                // new local images
                ..._newImages
                    .asMap()
                    .entries
                    .map((entry) {
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            entry.value,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (_isEditing)
                        Positioned(
                          top: 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: () =>
                                setState(
                                        () => _newImages.removeAt(entry.key)),
                            child: _removeButton(),
                          ),
                        ),
                    ],
                  );
                }),
                // add more tile (edit mode only)
                if (_isEditing)
                  GestureDetector(
                    onTap: () async {
                      final images = await _imageService.pickMultiImages();
                      if (images.isNotEmpty) {
                        setState(() => _newImages.addAll(images));
                      }
                    },
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.grey.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.grey[400]),
                          Text("Add more",
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          if (_isEditing)
            InkWell(
              onTap: () async {
                final images = await _imageService.pickMultiImages();
                if (images.isNotEmpty) {
                  setState(() => _newImages = images);
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Icon(Icons.image_outlined, color: Colors.grey[400]),
                    const SizedBox(height: 4),
                    Text("Tap to add photos",
                        style:
                        TextStyle(fontSize: 13, color: Colors.grey[500])),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 90,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library_outlined,
                        color: Colors.grey[400], size: 24),
                    const SizedBox(height: 4),
                    Text("No photos",
                        style:
                        TextStyle(fontSize: 12, color: Colors.grey[400])),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // ── employees section ─────────────────────────────────────────
  Widget _buildEmployeesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel("Employees"),
        const SizedBox(height: 8),
        EmployeePicker(
          allEmployees: _allEmployees,
          selectedEmployees: _selectedEmployees,
          selectable: _isEditing,
          onToggle: (employee) => setState(() {
            if (_selectedEmployees.any((e) => e.id == employee.id)) {
              _selectedEmployees.removeWhere((e) => e.id == employee.id);
            } else {
              _selectedEmployees.add(employee);
            }
          }),
        ),
      ],
    );
  }

  // ── action buttons ────────────────────────────────────────────
  Widget _buildActionButtons() {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _cancelEdit,
              child: const Text("Cancel"),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _save,
              child: const Text("Save changes"),
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
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: widget.onDelete,
            child: const Text("Delete"),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => setState(() => _isEditing = true),
            child: const Text("Edit"),
          ),
        ),
      ],
    );
  }

  // ── helpers ───────────────────────────────────────────────────
  Widget _removeButton() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.close, size: 14, color: Colors.white),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Colors.grey[400],
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _label(String text, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
          if (optional)
            Text(" (optional)",
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
      ),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

//
//   Widget _sectionLabel(String text) {
//     return Text(
//       text.toUpperCase(),
//       style: TextStyle(
//         fontSize: 11,
//         fontWeight: FontWeight.w500,
//         color: Colors.grey[400],
//         letterSpacing: 0.5,
//       ),
//     );
//   }
//
//   InputDecoration _inputDecoration(String hint) {
//     return InputDecoration(
//       hintText: hint,
//       hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
//       border: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(10),
//         borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
//       ),
//       enabledBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(10),
//         borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
//       ),
//       contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
//     );
//   }





