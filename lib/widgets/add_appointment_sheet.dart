import 'package:flutter/material.dart';
import '../models/appointment_record.dart';

import 'dart:io';

import '../models/client_record.dart';
import '../models/employee_record.dart';
import '../services/client_service.dart';
import '../services/user_service.dart';
import '../utils/images_utils/image_picker_service.dart';
import '../utils/images_utils/image_storage_service.dart';
import '../utils/images_utils/image_compress_service.dart';
import '../utils/date_utils_helper.dart';

class AddEventSheet extends StatefulWidget {
  const AddEventSheet({super.key});

  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  final _formKey = GlobalKey<FormState>();
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
  final _imageService = ImagePickerService();
  final _storageService = ImageStorageService();
  final _compressService = ImageCompressService();
  final _clientService = ClientService();
  final _userService = UserService();

  @override
  void initState() {
    super.initState();
    _loadEmployees();
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

  Future<void> _loadEmployees() async {
    _userService.employeesStream().listen((employees) {
      if (mounted) setState(() => _allEmployees = employees);
    });
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
    } catch (e) {
      if (mounted) setState(() => _isSearchingClient = false);
    }
  }

  void _selectClient(ClientRecord client) {
    setState(() {
      _selectedClient = client;
      _clientSearchController.text = client.displayName;
      _clientResults = [];
    });
  }

  void _toggleEmployee(EmployeeRecord employee) {
    setState(() {
      if (_selectedEmployees.any((e) => e.id == employee.id)) {
        _selectedEmployees.removeWhere((e) => e.id == employee.id);
      } else {
        _selectedEmployees.add(employee);
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
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedStartTime ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      _selectedStartTime = picked;
      _startTimeController.text = picked.format(context);
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedEndTime ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      _selectedEndTime = picked;
      _endTimeController.text = picked.format(context);
    });
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _submit(BuildContext rootContext) async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedClient == null) {
      ScaffoldMessenger.of(
        rootContext,
      ).showSnackBar(const SnackBar(content: Text("Please select a client")));
      return;
    }

    if (_selectedEmployees.isEmpty) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(content: Text("Please select at least one employee")),
      );
      return;
    }

    try {
      // final compressed = await _compressService.compressImages(_selectedImages);
      // final imageUrls = await _storageService.uploadImages(compressed);

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
        pictures: const [],
        // imageUrls when implemented
        status: 'booked',
      );

      if (rootContext.mounted) Navigator.pop(rootContext, newAppointment);
    } catch (e) {
      if (rootContext.mounted) {
        ScaffoldMessenger.of(
          rootContext,
        ).showSnackBar(const SnackBar(content: Text("Something went wrong")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rootContext = context;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // Title
                Text(
                  "Add New Job",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),

                const SizedBox(height: 24),

                _label("Job Title"),
                TextFormField(
                  controller: _titleController,
                  decoration: _inputDecoration("e.g. Plumbing repair"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Title is required" : null,
                ),

                const SizedBox(height: 16),

                // Date
                _label("Date"),
                TextFormField(
                  controller: _dateController,
                  readOnly: true,
                  decoration: _inputDecoration("Select date").copyWith(
                    suffixIcon: const Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Please select a date" : null,
                  onTap: _pickDate,
                ),

                const SizedBox(height: 16),

                // Start time + End time side by side
                _label("Time"),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _startTimeController,
                        readOnly: true,
                        decoration: _inputDecoration("Start time").copyWith(
                          suffixIcon: const Icon(
                            Icons.access_time_outlined,
                            size: 18,
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? "Required" : null,
                        onTap: _pickStartTime,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _endTimeController,
                        readOnly: true,
                        decoration: _inputDecoration("End time").copyWith(
                          suffixIcon: const Icon(
                            Icons.access_time_outlined,
                            size: 18,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return "Required";
                          if (_selectedStartTime != null &&
                              _selectedEndTime != null) {
                            final start =
                                _selectedStartTime!.hour * 60 +
                                _selectedStartTime!.minute;
                            final end =
                                _selectedEndTime!.hour * 60 +
                                _selectedEndTime!.minute;
                            if (end <= start) {
                              return "Must be after start";
                            }
                          }
                          return null;
                        },
                        onTap: _pickEndTime,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Client search
                _label("Client"),
                TextFormField(
                  controller: _clientSearchController,
                  decoration: _inputDecoration("Search by name or phone number")
                      .copyWith(
                        suffixIcon: _selectedClient != null
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() {
                                  _selectedClient = null;
                                  _clientSearchController.clear();
                                  _clientResults = [];
                                }),
                              )
                            : _isSearchingClient
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Icon(Icons.search, size: 18),
                      ),
                  readOnly: _selectedClient != null,
                  validator: (v) =>
                      v == null || v.isEmpty ? "Please select a client" : null,
                  onChanged: _searchClients,
                ),

                // client search results dropdown
                if (_clientResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: _clientResults.map((client) {
                        return ListTile(
                          dense: true,
                          title: Text(
                            client.displayName,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            client.phone,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => _selectClient(client),
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 16),

                // Notes
                _label("Notes", optional: true),
                TextFormField(
                  controller: _notesController,
                  decoration: _inputDecoration("Type the note here..."),
                  maxLines: 3,
                ),

                const SizedBox(height: 16),

                // Materials
                _label("Materials needed", optional: true),
                TextFormField(
                  controller: _materialsController,
                  decoration: _inputDecoration("Type the materials here..."),
                ),

                const SizedBox(height: 16),

                // Pictures
                _label("Pictures", optional: true),
                if (_selectedImages.isNotEmpty) ...[
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _selectedImages.length) {
                          return GestureDetector(
                            onTap: () async {
                              final images = await _imageService
                                  .pickMultiImages();
                              if (images.isNotEmpty) {
                                setState(() => _selectedImages.addAll(images));
                              }
                            },
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.4),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add, color: Colors.grey[400]),
                                  Text(
                                    "Add more",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _selectedImages[index],
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: () => setState(
                                  () => _selectedImages.removeAt(index),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ] else
                  InkWell(
                    onTap: () async {
                      final images = await _imageService.pickMultiImages();
                      if (images.isNotEmpty) {
                        setState(() => _selectedImages = images);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.image_outlined, color: Colors.grey[400]),
                          const SizedBox(height: 4),
                          Text(
                            "Tap to add photos",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Employee selector
                _label("Select employees"),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _allEmployees.isEmpty
                      ? Center(
                          child: Text(
                            "No employees found",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        )
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _allEmployees.map((employee) {
                            final isSelected = _selectedEmployees.any(
                              (e) => e.id == employee.id,
                            );

                            return GestureDetector(
                              onTap: () => _toggleEmployee(employee),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: employee.color.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                      border: isSelected
                                          ? Border.all(
                                              color: employee.color,
                                              width: 2.5,
                                            )
                                          : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        employee.initials,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: employee.color,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      employee.name.split(' ').first,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),

                const SizedBox(height: 24),
                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _submit(rootContext),
                    child: const Text(
                      "Create event",
                      style: TextStyle(fontSize: 15),
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
}

Widget _label(String text, {bool optional = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        if (optional)
          Text(
            " (optional)",
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
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
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}
