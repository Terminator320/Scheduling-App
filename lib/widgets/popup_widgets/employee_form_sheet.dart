import 'package:flutter/material.dart';

import '../../models/employee_record.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../../utils/calendar_utils/form_widgets.dart';
import '../employee_widgets/employee_color_picker_row.dart';
import '../sheet_widgets.dart';


class EmployeeFormSheet extends StatefulWidget {
  const EmployeeFormSheet({super.key, this.employee});

  final EmployeeRecord? employee;

  @override
  State<EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends State<EmployeeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _service = UserService();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  late bool _isAdmin;
  late Color _selectedColor;
  bool _isSaving = false;

  bool get _isEdit => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _nameController = TextEditingController(text: e?.name ?? '');
    _emailController = TextEditingController(text: e?.email ?? '');
    _phoneController = TextEditingController(text: e?.phone ?? '');
    _isAdmin = e?.isAdmin ?? false;
    _selectedColor = e?.color ?? Colors.blue.shade500;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }


  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Delete employee')),
        content: Text(
          tr(ctx, 'Are you sure you want to delete this employee?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'Cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _service.deleteEmployee(widget.employee!.id);
    if (!mounted) return;
    Navigator.pop(context, 'deleted');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim().toLowerCase();
      final phone = _phoneController.text.trim();
      final colorValue = _selectedColor.toARGB32().toString();

      if (_isEdit) {
        await _service.updateEmployee(
          docId: widget.employee!.id,
          name: name,
          email: email,
          phone: phone,
          colorValue: colorValue,
          isAdmin: _isAdmin,
        );
      } else {
        await _service.addEmployee(
          name: name,
          email: email,
          phone: phone,
          colorValue: colorValue,
          isAdmin: _isAdmin,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _requiredValidator(String? value) {
    return (value == null || value.trim().isEmpty)
        ? tr(context, 'Name and email are required')
        : null;
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isEdit
        ? tr(context, 'Edit Employee')
        : tr(context, 'Create Employee');
    final submitLabel = _isEdit
        ? tr(context, 'Update Employee')
        : tr(context, 'Create Employee');

    return SheetFrame(
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                decoration: formInputDecoration(context, tr(context, 'Name')),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: formInputDecoration(context, tr(context, 'Email')),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: formInputDecoration(
                  context,
                  tr(context, 'Phone number'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr(context, 'Employee Color'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              EmployeeColorPickerRow(
                selected: _selectedColor,
                onSelect: (c) => setState(() => _selectedColor = c),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v),
                title: Text(tr(context, 'Give admin mode access')),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(submitLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
