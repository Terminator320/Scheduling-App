import 'package:flutter/material.dart';
import '../../models/employee_record.dart';

class EmployeePicker extends StatelessWidget {
  final List<EmployeeRecord> allEmployees;
  final List<EmployeeRecord> selectedEmployees;
  final bool selectable;
  final bool hasError;
  final Function(EmployeeRecord)? onToggle;

  const EmployeePicker({
    super.key,
    required this.allEmployees,
    required this.selectedEmployees,
    this.selectable = true,
    this.hasError = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final displayEmployees = selectable
        ? allEmployees
        : allEmployees
              .where((e) => selectedEmployees.any((s) => s.id == e.id))
              .toList();

    if (displayEmployees.isEmpty) {
      return Text(
        selectable ? "No employees found" : "No employees assigned",
        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: hasError
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: displayEmployees.isEmpty
          ? Text(
              selectable ? "No employees found" : "No employees assigned",
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: displayEmployees.map((employee) {
                final isSelected = selectedEmployees.any(
                  (e) => e.id == employee.id,
                );

                return GestureDetector(
                  onTap: selectable ? () => onToggle?.call(employee) : null,
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
                              ? Border.all(color: employee.color, width: 2.5)
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
                        width: 52,
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
    );
  }
}
