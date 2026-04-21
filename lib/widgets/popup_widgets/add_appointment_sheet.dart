import 'package:flutter/material.dart';
import '../../models/appointment_record.dart';
import '../../models/appointmentImage.dart';

import 'dart:io';

import '../../models/client_record.dart';
import '../../models/employee_record.dart';
import '../../services/client_service.dart';
import '../../services/user_service.dart';
import '../../utils/calendar_utils/form_widgets.dart';
import '../../utils/images_utils/image_picker_service.dart';
import '../../utils/images_utils/image_storage_service.dart';
import '../../utils/images_utils/image_compress_service.dart';
import '../../utils/date_utils_helper.dart';
import '../calendar_widgets/employee_picker.dart';
import '../calendar_widgets/photo_picker_section.dart';
import '../calendar_widgets/time_range_row.dart';
import '../client_search_field.dart';

class AddEventSheet extends StatefulWidget {
  const AddEventSheet({super.key});

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
  final _notesController = TextEditingController();
  final _materialsController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;

  ClientRecord? _selectedClient;
  List<ClientRecord> _clientResults = [];
  bool _isSearchingClient = false;

  List<EmployeeRecord> _allEmployees = [];
  List<EmployeeRecord> _selectedEmployees = [];

  List<File> _selectedImages = [];
  bool _isSubmitting = false;
  final _imageService = ImagePickerService();
  final _storageService = ImageStorageService();
  final _compressService = ImageCompressService();
  final _clientService = ClientService();
  final _userService = UserService();

  @override
  void initState() {
    super.initState();
    _userService.employeesStream().listen((employees) {
      if (mounted) setState(() => _allEmployees = employees);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _dateController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _clientSearchController.dispose();
    _notesController.dispose();
    _materialsController.dispose();
    super.dispose();
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
      if (mounted) {
        setState(() {
          _clientResults = results;
          _isSearchingClient = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingClient = false);
    }
  }

  void _selectClient(ClientRecord client) {
    setState(() {
      _selectedClient = client;
      _clientSearchController.text = client.displayName;
      _clientResults = [];
      _errors['client'] = null;
    });
  }

  void _clearClient() {
    setState(() {
      _selectedClient = null;
      _clientSearchController.clear();
      _clientResults = [];
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
    });
  }

  Future<void> _pickEndTime() async {
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
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _showSnack(BuildContext ctx, String message) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _submit(BuildContext ctx) async {
    setState(() {
      _errors['title'] = _titleController.text.trim().isEmpty ? "Title is required" : null;
      _errors['date'] = _selectedDate == null ? "Please select a date" : null;
      _errors['startTime'] = _selectedStartTime == null ? "Please select a start time" : null;
      _errors['endTime'] = _selectedEndTime == null
          ? "Please select an end time"
          : (_selectedStartTime != null &&
          (_selectedEndTime!.hour * 60 + _selectedEndTime!.minute) <=
              (_selectedStartTime!.hour * 60 + _selectedStartTime!.minute))
          ? "Must be after start time"
          : null;
      _errors['client'] = _selectedClient == null ? "Please select a client" : null;
      _errors['employees'] = _selectedEmployees.isEmpty ? "Please select at least one employee" : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    setState(() => _isSubmitting = true);

    try {
      List<AppointmentImage> uploadedImages = const [];
      if (_selectedImages.isNotEmpty) {
        final compressed = await _compressService.compressImages(_selectedImages);
        uploadedImages = await _storageService.uploadImages(compressed);
      }

      final startTime = _combineDateAndTime(
        _selectedDate!,
        _selectedStartTime!,
      );
      final endTime = _combineDateAndTime(_selectedDate!, _selectedEndTime!);

      final newAppointment = AppointmentRecord(
        title: _titleController.text.trim(),
        startTime: startTime,
        endTime: endTime,
        clientId: _selectedClient!.id,
        clientName: _selectedClient!.displayName,
        clientPhone: _selectedClient!.phone,
        address: _selectedClient!.address,
        employeeIds: _selectedEmployees.map((e) => e.id).toList(),
        employeeNames: _selectedEmployees.map((e) => e.name).toList(),
        notes: _notesController.text.trim(),
        materialsNeeded: _materialsController.text.trim(),
        pictures: uploadedImages,
        status: 'booked',
      );

      if (ctx.mounted) Navigator.pop(ctx, newAppointment);
    } catch (_) {
      if (ctx.mounted) {
        setState(() => _isSubmitting = false);
        _showSnack(ctx, "Something went wrong uploading photos");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (sheetContext, scrollController) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(sheetContext).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                Text(
                  "Add New Job",
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.headlineLarge,
                ),
                const SizedBox(height: 24),

                formLabel(sheetContext, "Job Title"),
                TextField(
                  controller: _titleController,
                  decoration: formInputDecoration(sheetContext, "e.g. Plumbing repair").copyWith(
                    errorText: _errors['title'],
                  ),
                  onChanged: (_) => setState(() => _errors['title'] = null),
                ),
                const SizedBox(height: 16),

                formLabel(sheetContext, "Date"),
                TextField(
                  controller: _dateController,
                  readOnly: true,
                  decoration: formInputDecoration(sheetContext, "Select date").copyWith(
                    suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                    errorText: _errors['date'],
                  ),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 16),

                formLabel(sheetContext, "Time"),
                TimeRangeRow(
                  startController: _startTimeController,
                  endController: _endTimeController,
                  selectedStart: _selectedStartTime,
                  selectedEnd: _selectedEndTime,
                  onTapStart: _pickStartTime,
                  onTapEnd: _pickEndTime,
                  startError: _errors['startTime'],
                  endError: _errors['endTime'],
                ),
                const SizedBox(height: 16),

                formLabel(sheetContext, "Client"),
                ClientSearchField(
                  controller: _clientSearchController,
                  selectedClient: _selectedClient,
                  results: _clientResults,
                  isSearching: _isSearchingClient,
                  onChanged: _searchClients,
                  onSelect: _selectClient,
                  onClear: _clearClient,
                  errorText: _errors['client'],
                ),
                const SizedBox(height: 16),

                formLabel(sheetContext, "Notes", optional: true),
                TextField(
                  controller: _notesController,
                  decoration: formInputDecoration(sheetContext, "Type the note here..."),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                formLabel(sheetContext, "Materials needed", optional: true),
                TextField(
                  controller: _materialsController,
                  decoration: formInputDecoration(sheetContext, "Type the materials here..."),
                ),
                const SizedBox(height: 16),

                formLabel(sheetContext, "Pictures", optional: true),
                PhotoPickerSection(
                  existingImages: const [],
                  newImages: _selectedImages,
                  isEditing: true,
                  onPickImages: () async {
                    final images = await _imageService.pickMultiImages();
                    if (images.isNotEmpty) setState(() => _selectedImages.addAll(images));
                  },
                  onRemoveExisting: (_) {},
                  onRemoveNew: (i) => setState(() => _selectedImages.removeAt(i)),
                ),
                const SizedBox(height: 16),

                formLabel(sheetContext, "Select employees"),
                EmployeePicker(
                  allEmployees: _allEmployees,
                  selectedEmployees: _selectedEmployees,
                  onToggle: _toggleEmployee,
                  hasError: _errors['employees'] != null,
                ),
                if (_errors['employees'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(
                      _errors['employees']!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(sheetContext).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : () => _submit(sheetContext),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            "Create event",
                            style: Theme.of(sheetContext).textTheme.titleSmall,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------  drag handle  --------------
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
}
