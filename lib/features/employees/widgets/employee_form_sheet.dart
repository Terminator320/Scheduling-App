import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/features/employees/widgets/employee_color_picker_row.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';


class EmployeeFormSheet extends StatefulWidget {
  const EmployeeFormSheet({super.key, this.employee});

  final EmployeeRecord? employee;

  @override
  State<EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends State<EmployeeFormSheet> {
  final _service = UserService();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  late bool _isAdmin;
  late int _selectedColor;
  bool _isSaving = false;
  final Map<String, String?> _errors = {};

  bool get _isEdit => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _nameController = TextEditingController(text: e?.name ?? '');
    _emailController = TextEditingController(text: e?.email ?? '');
    _phoneController = TextEditingController(text: e?.phone ?? '');
    _isAdmin = e?.isAdmin ?? false;
    _selectedColor = e?.color.toARGB32() ?? AppColors.employeePalette.first.toARGB32();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool _validate() {
    final errors = <String, String?>{};
    if (_nameController.text.trim().isEmpty) {
      errors['name'] = context.l10n.nameAndEmailAreRequired;
    }
    if (_emailController.text.trim().isEmpty) {
      errors['email'] = context.l10n.nameAndEmailAreRequired;
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    return errors.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;

    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim().toLowerCase();
      final phone = _phoneController.text.trim();
      final colorValue = _selectedColor.toString();

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
      final message = e.toString().contains('Employee email already exists')
          ? context.l10n.anEmployeeWithThisEmailAlreadyExists
          : context.l10n.couldNotCreateEmployee;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isEdit
        ? context.l10n.editEmployee
        : context.l10n.createEmployee;
    final submitLabel = _isEdit
        ? context.l10n.updateEmployee
        : context.l10n.createEmployee;

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
            Text(title, style: theme.textTheme.headlineLarge),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 20),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.name2,
                controller: _nameController,
                required: true,
                errorText: _errors['name'],
                onChanged: (_) {
                  if (_errors['name'] != null) {
                    setState(() => _errors['name'] = null);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.email,
                controller: _emailController,
                keyboard: TextInputType.emailAddress,
                required: true,
                errorText: _errors['email'],
                onChanged: (_) {
                  if (_errors['email'] != null) {
                    setState(() => _errors['email'] = null);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.phoneNumber,
                controller: _phoneController,
                keyboard: TextInputType.phone,
                optional: true,
              ),
            ),
            const SizedBox(height: 16),
            EmployeeColorPickerRow(
              selectedColor: _selectedColor,
              onColorChanged: (value) => setState(() => _selectedColor = value),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isAdmin,
              onChanged: (v) => setState(() => _isAdmin = v),
              title: Text(context.l10n.giveAdminModeAccess),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Text(submitLabel),
            ),
          ],
        );
      },
    );
  }
}
