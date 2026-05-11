import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/services/image_picker_service.dart';
import 'package:scheduling/core/services/image_storage_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/cupertino_time_picker.dart';
import 'package:scheduling/features/calendar/widgets/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/photo_picker_section.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/client_search_field.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';


class EventDetailsSheet extends ConsumerStatefulWidget {

  const EventDetailsSheet({
    required this.appointment, super.key,
    this.showActions = true,
    this.initialEditing = false,
  });
  final AppointmentRecord appointment;
  final bool showActions;
  final bool initialEditing;

  @override
  ConsumerState<EventDetailsSheet> createState() => _EventDetailsSheetState();
}

class _EventDetailsSheetState extends ConsumerState<EventDetailsSheet> {
  bool _isEditing = false;
  final Map<String, String?> _errors = {};

  late final TextEditingController _titleController;
  late final TextEditingController _dateController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;
  late final TextEditingController _clientSearchController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  late final TextEditingController _materialsController;

  late DateTime _selectedDate;
  late TimeOfDay _selectedStartTime;
  late TimeOfDay _selectedEndTime;
  late String _editingStatus;

  List<EmployeeRecord> _allEmployees = [];
  List<EmployeeRecord> _selectedEmployees = [];
  List<AppointmentImage> _existingImages = [];
  final List<AppointmentImage> _removedExistingImages = [];
  final List<File> _newImages = [];
  bool _isSaving = false;
  ClientRecord? _client;
  StreamSubscription<List<EmployeeRecord>>? _employeesSub;
  ClientRecord? _selectedClient;
  List<ClientRecord> _clientResults = [];
  bool _isSearchingClient = false;

  late final AppointmentImageUploadService _imageUploadService;
  late final ClientsRepository _clientService;
  late final AppointmentsRepository _appointmentRepo;
  final _storageService = ImageStorageService();
  final _imageService = ImagePickerService();

  @override
  void initState() {
    super.initState();
    _imageUploadService = ref.read(appointmentImageUploadProvider);
    _clientService = ref.read(clientsRepositoryProvider);
    _appointmentRepo = ref.read(appointmentsRepositoryProvider);
    _isEditing = widget.initialEditing;
    final a = widget.appointment;

    _titleController = TextEditingController(text: a.title);
    _dateController = TextEditingController(text: DateUtilsHelper.formatDate(a.startTime));
    _startTimeController = TextEditingController(text: DateUtilsHelper.formatTime(a.startTime));
    _endTimeController = TextEditingController(text: DateUtilsHelper.formatTime(a.endTime));
    _clientSearchController = TextEditingController(text: a.clientName);
    _addressController = TextEditingController(text: a.address);
    _notesController = TextEditingController(text: a.notes);
    _materialsController = TextEditingController(text: a.materialsNeeded);

    _selectedDate = a.startTime;
    _selectedStartTime = TimeOfDay.fromDateTime(a.startTime);
    _selectedEndTime = TimeOfDay.fromDateTime(a.endTime);
    _editingStatus = a.status;
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
    final employeesRepo = ref.read(employeesRepositoryProvider);
    _employeesSub = employeesRepo.watchEmployees().listen((employees) {
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
      await _appointmentRepo.updateAppointmentStatus(id: id, status: 'done');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.somethingWentWrong)));
      }
    }
  }

  Future<void> _cancelAppointment() async {
    final id = widget.appointment.id;
    if (id == null) return;
    setState(() => _isSaving = true);
    try {
      await _appointmentRepo.updateAppointmentStatus(id: id, status: 'cancelled');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.somethingWentWrong)));
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _errors['title'] = _titleController.text.trim().isEmpty ? context.l10n.titleIsRequired : null;
      _errors['date'] = _dateController.text.trim().isEmpty ? context.l10n.pleaseSelectADate : null;
      _errors['startTime'] = _startTimeController.text.trim().isEmpty ? context.l10n.pleaseSelectAStartTime : null;
      _errors['endTime'] = _endTimeController.text.trim().isEmpty
          ? context.l10n.pleaseSelectAnEndTime
          : (() {
              final start = _selectedStartTime.hour * 60 + _selectedStartTime.minute;
              final end = _selectedEndTime.hour * 60 + _selectedEndTime.minute;
              return end <= start ? context.l10n.mustBeAfterStartTime : null;
            })();
      _errors['client'] = _selectedClient == null && widget.appointment.clientId.trim().isEmpty
          ? context.l10n.pleaseSelectAClient
          : null;
      _errors['employees'] = _selectedEmployees.isEmpty ? context.l10n.pleaseSelectAtLeastOneEmployee : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    if (_selectedEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pleaseSelectAtLeastOneEmployee)),
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

    setState(() => _isSaving = true);

    try {
      final appointmentId = widget.appointment.id;
      if (appointmentId == null) throw StateError('Cannot save an appointment without an id.');

      if (_removedExistingImages.isNotEmpty) {
        await _storageService.deleteImages(_removedExistingImages);
      }

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
        status: _editingStatus,
      );

      await _appointmentRepo.updateAppointment(updated);

      if (mounted) setState(() => _isEditing = false);
      if (mounted) Navigator.pop(context, updated);

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
          SnackBar(content: Text(context.l10n.somethingWentWrongSavingChanges)),
        );
      }
    }
  }

  Future<void> _deleteAppointment() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteAppointment),
        content: Text(context.l10n.areYouSureYouWantToDeleteThisJob),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _appointmentRepo.deleteAppointment(widget.appointment.id!);
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
            const SizedBox(height: AppSpacing.sp8),
            if (_isEditing && widget.appointment.status.toLowerCase() != 'cancelled')
              ..._buildEditContent(sheetContext)
            else
              ..._buildViewContent(sheetContext),
          ],
        );
      },
    );
  }

  // ── VIEW MODE ─────────────────────────────────────────────────────────────

  List<Widget> _buildViewContent(BuildContext ctx) {
    final a = widget.appointment;
    final theme = Theme.of(ctx);
    final scheme = theme.colorScheme;
    final isCancelled = a.status.toLowerCase() == 'cancelled';
    final isDone = a.status.toLowerCase() == 'done' || a.status.toLowerCase() == 'completed';
    final now = DateTime.now();
    final isToday = a.startTime.year == now.year &&
        a.startTime.month == now.month &&
        a.startTime.day == now.day;

    return [
      // Edit button — top right
      if (widget.showActions && !isCancelled)
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => setState(() => _isEditing = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant, width: 1.5),
                borderRadius: BorderRadius.circular(AppRadius.r8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined, size: 13, color: scheme.onSurface),
                  const SizedBox(width: 5),
                  Text(
                    ctx.l10n.edit,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

      // Centered header
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
        child: Column(
          children: [
            Text(
              a.title,
              style: theme.textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sp8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      DateUtilsHelper.formatDate(a.startTime),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time_outlined, size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '${DateUtilsHelper.formatTime(a.startTime)} – ${DateUtilsHelper.formatTime(a.endTime)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sp16),
      const Divider(height: 1),
      const SizedBox(height: AppSpacing.sp16),

      // Client
      _SectionRow(
        label: ctx.l10n.client,
        value: _client?.displayName ?? a.clientName,
        subtitle: a.clientPhone.isNotEmpty ? a.clientPhone : ctx.l10n.noNumber,
      ),
      if ((_client?.contacts ?? const <ClientContact>[]).isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sp12),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctx.l10n.contacts,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: AppSpacing.sp8),
              ..._client!.contacts.map(_contactCard),
            ],
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.sp16),

      // Address (tappable if has address)
      _AddressRow(
        label: ctx.l10n.address,
        address: a.address.isNotEmpty ? a.address : ctx.l10n.noAddress,
        onTap: a.address.isNotEmpty
            ? () => AddressMapLauncher.showMapChoices(ctx, address: a.address)
            : null,
      ),
      const SizedBox(height: AppSpacing.sp16),

      // Notes
      _SectionRow(
        label: ctx.l10n.notes,
        value: a.notes.isNotEmpty ? a.notes : ctx.l10n.noNotes,
      ),
      const SizedBox(height: AppSpacing.sp16),

      // Materials
      _buildMaterialsView(a, theme),
      const SizedBox(height: AppSpacing.sp16),

      // Employees
      _buildEmployeesView(theme),
      const SizedBox(height: AppSpacing.sp16),

      // Photos
      _buildPhotosView(theme),

      // Actions
      if (widget.showActions) ...[
        const SizedBox(height: AppSpacing.sp24),

        // Mark as Done
        if (isToday && !isDone && !isCancelled)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: AppColors.success,
            ),
            onPressed: _isSaving ? null : _markAsDone,
            icon: _isSaving
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(ctx.l10n.markAsDone),
          ),

        if (isDone) ...[
          const SizedBox(height: AppSpacing.sp8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: AppColors.success,
              side: const BorderSide(color: AppColors.success),
            ),
            onPressed: null,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(ctx.l10n.completed),
          ),
        ],

        if (!isCancelled) ...[
          if (isToday && !isDone) const SizedBox(height: AppSpacing.sp8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
            onPressed: _isSaving ? null : _cancelAppointment,
            icon: const Icon(Icons.close, size: 15),
            label: Text(ctx.l10n.cancelAppointment),
          ),
          const SizedBox(height: 5),
          Center(
            child: Text(
              ctx.l10n.cancelledJobsAreSavedToHistory,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    ];
  }

  Widget _buildMaterialsView(AppointmentRecord a, ThemeData theme) {
    final scheme = theme.colorScheme;
    return _SectionRow(
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
                    (m) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(AppRadius.rFull),
                      ),
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            )
          : null,
    );
  }

  Widget _buildEmployeesView(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.employees.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        if (_selectedEmployees.isEmpty)
          Text(
            context.l10n.noEmployeesAssigned,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          ..._selectedEmployees.map((e) => _EmployeePillView(employee: e)),
      ],
    );
  }

  Widget _buildPhotosView(ThemeData theme) {
    final id = widget.appointment.id;
    final isCancelled = widget.appointment.status.toLowerCase() == 'cancelled';
    final notifier = ref.read(photoUploadNotifierProvider);
    final failure = id != null ? notifier.failureFor(id) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.pictures.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: AppSpacing.sp8),
        PhotoPickerSection(
          existingImages: _existingImages,
          newImages: _newImages,
          isEditing: false,
          onPickImages: () {},
          onRemoveExisting: (_) {},
          onRemoveNew: (_) {},
          failedCount: failure?.failedCount ?? 0,
          tooLargeFileNames: failure?.tooLargeFileNames ?? const [],
          onRetry: (failure?.failedCount ?? 0) > 0 && !isCancelled
              ? () {
                  notifier.clearFailure(id!);
                  setState(() => _isEditing = true);
                }
              : null,
        ),
      ],
    );
  }

  Widget _contactCard(ClientContact contact) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(AppSpacing.sp12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r12),
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
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
          ),
        ],
      ),
    );
  }

  // ── EDIT MODE ─────────────────────────────────────────────────────────────

  List<Widget> _buildEditContent(BuildContext ctx) {
    final theme = Theme.of(ctx);
    final scheme = theme.colorScheme;

    return [
      // Title
      Text(ctx.l10n.editAppointment, style: theme.textTheme.headlineLarge),
      const SizedBox(height: AppSpacing.sp16),
      const Divider(height: 1),
      const SizedBox(height: AppSpacing.sp16),

      // Service / Title
      SheetFocusScroll(
        child: LabeledTextField(
          label: ctx.l10n.serviceTitle,
          hint: ctx.l10n.eGPlumbingRepair,
          controller: _titleController,
          required: true,
          errorText: _errors['title'],
          onChanged: (_) {
            if (_errors['title'] != null) setState(() => _errors['title'] = null);
          },
        ),
      ),
      const SizedBox(height: AppSpacing.sp16),

      // Client
      formLabel(ctx, ctx.l10n.client, required: true),
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

      // Assigned Employee
      formLabel(ctx, ctx.l10n.assignedEmployee),
      const SizedBox(height: 6),
      EmployeePicker(
        allEmployees: _allEmployees,
        selectedEmployees: _selectedEmployees,
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
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            _errors['employees']!,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ),
      const SizedBox(height: AppSpacing.sp16),

      // Date — full width
      SheetFocusScroll(
        child: LabeledTextField(
          label: ctx.l10n.date,
          hint: ctx.l10n.selectDate,
          controller: _dateController,
          required: true,
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
      const SizedBox(height: AppSpacing.sp16),

      // Start time + End time side-by-side
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SheetFocusScroll(
              child: LabeledTextField(
                label: ctx.l10n.startTime,
                hint: ctx.l10n.start,
                controller: _startTimeController,
                required: true,
                readOnly: true,
                errorText: _errors['startTime'],
                onTap: () async {
                  final picked = await showCupertinoTimePicker(context, initialTime: _selectedStartTime);
                  if (picked == null) return;
                  setState(() {
                    _selectedStartTime = picked;
                    _startTimeController.text = picked.format(context);
                    _errors['startTime'] = null;
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sp12),
          Expanded(
            child: SheetFocusScroll(
              child: LabeledTextField(
                label: ctx.l10n.endTime,
                hint: ctx.l10n.end,
                controller: _endTimeController,
                required: true,
                readOnly: true,
                errorText: _errors['endTime'],
                onTap: () async {
                  final picked = await showCupertinoTimePicker(context, initialTime: _selectedEndTime);
                  if (picked == null) return;
                  setState(() {
                    _selectedEndTime = picked;
                    _endTimeController.text = picked.format(context);
                    _errors['endTime'] = null;
                  });
                },
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sp16),

      // Status picker
      formLabel(ctx, ctx.l10n.appointmentStatus),
      const SizedBox(height: 6),
      _buildStatusPicker(),
      const SizedBox(height: AppSpacing.sp16),

      // Address
      SheetFocusScroll(
        child: AddressAutocompleteField(
          controller: _addressController,
          optional: true,
        ),
      ),
      const SizedBox(height: AppSpacing.sp16),

      // Materials
      SheetFocusScroll(
        child: LabeledTextField(
          label: ctx.l10n.materialsNeeded,
          hint: ctx.l10n.eGPipeWrenchTapeCommaSeparated,
          controller: _materialsController,
          optional: true,
          maxLines: 2,
        ),
      ),
      const SizedBox(height: AppSpacing.sp16),

      // Notes
      SheetFocusScroll(
        child: LabeledTextField(
          label: ctx.l10n.notes,
          hint: ctx.l10n.typeTheNoteHere,
          controller: _notesController,
          optional: true,
          maxLines: 2,
        ),
      ),
      const SizedBox(height: AppSpacing.sp16),

      // Photos
      formLabel(ctx, ctx.l10n.pictures, optional: true),
      PhotoPickerSection(
        existingImages: _existingImages,
        newImages: _newImages,
        isEditing: true,
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
      const SizedBox(height: AppSpacing.sp24),

      // Save button
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
        onPressed: _isSaving ? null : _save,
        child: _isSaving
            ? SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
              )
            : Text(ctx.l10n.saveChanges),
      ),
      const SizedBox(height: AppSpacing.sp8),

      // Delete button
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 44),
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
        ),
        onPressed: _isSaving ? null : _deleteAppointment,
        child: Text(ctx.l10n.deleteAppointment),
      ),
    ];
  }

  Widget _buildStatusPicker() {
    final scheme = Theme.of(context).colorScheme;
    const statuses = ['confirmed', 'in_progress', 'pending', 'done', 'cancelled'];
    const labels = {
      'confirmed': 'Confirmed',
      'in_progress': 'In Progress',
      'pending': 'Pending',
      'done': 'Done',
      'cancelled': 'Cancelled',
    };

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: statuses.map((s) {
        final isSelected = _editingStatus.toLowerCase() == s;
        return GestureDetector(
          onTap: () => setState(() => _editingStatus = s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? scheme.primaryContainer : Colors.transparent,
              border: Border.all(
                color: isSelected ? AppColors.primary : scheme.outlineVariant,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(AppRadius.rFull),
            ),
            child: Text(
              labels[s]!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Private view-mode widgets ─────────────────────────────────────────────

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.label,
    required this.value,
    this.subtitle,
    this.customValue,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Widget? customValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        customValue ?? Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.label, required this.address, this.onTap});

  final String label;
  final String address;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        if (onTap != null)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.r8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      address,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.open_in_new, size: 14, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          )
        else
          Text(address, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
      ],
    );
  }
}

class _EmployeePillView extends StatelessWidget {
  const _EmployeePillView({required this.employee});

  final EmployeeRecord employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r8 + 2),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: employee.color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                employee.initials,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (employee.email.isNotEmpty)
                  Text(
                    employee.email,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
