// test/employee_color_grid_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/widgets/employee_color_grid.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('EmployeeColorGrid renders 8 swatches plus custom button', (tester) async {
    await tester.pumpWidget(_wrap(EmployeeColorGrid(
      selectedColor: AppColors.employeePalette[0].toARGB32(),
      onColorSelected: (_) {},
    )));
    // 8 palette swatches + 1 custom "+" button = 9 GestureDetectors
    expect(find.byType(GestureDetector), findsNWidgets(9));
  });

  testWidgets('EmployeeColorGrid calls onColorSelected when tapping a swatch', (tester) async {
    int? selected;
    await tester.pumpWidget(_wrap(EmployeeColorGrid(
      selectedColor: AppColors.employeePalette[0].toARGB32(),
      onColorSelected: (v) => selected = v,
    )));
    await tester.tap(find.byType(GestureDetector).at(1));
    await tester.pump();
    expect(selected, AppColors.employeePalette[1].toARGB32());
  });

  testWidgets('EmployeeColorGrid shows checkmark on selected swatch', (tester) async {
    await tester.pumpWidget(_wrap(EmployeeColorGrid(
      selectedColor: AppColors.employeePalette[2].toARGB32(),
      onColorSelected: (_) {},
    )));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('EmployeeColorGrid shows custom button with add icon', (tester) async {
    await tester.pumpWidget(_wrap(EmployeeColorGrid(
      selectedColor: AppColors.employeePalette[0].toARGB32(),
      onColorSelected: (_) {},
    )));
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
