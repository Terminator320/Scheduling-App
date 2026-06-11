// test/employee_color_grid_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/widgets/fields/employee_color_grid.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  const palette = AppColors.employeePalette;

  testWidgets('renders every palette swatch plus the custom button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeColorGrid(
          selectedColor: palette[0].toARGB32(),
          onColorSelected: (_) {},
        ),
      ),
    );
    // All palette swatches + 1 custom rainbow button.
    expect(find.byType(InkResponse), findsNWidgets(palette.length + 1));
  });

  testWidgets('hides colors already used by another employee', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeColorGrid(
          selectedColor: palette[0].toARGB32(),
          onColorSelected: (_) {},
          usedColors: {palette[1].toARGB32(), palette[2].toARGB32()},
        ),
      ),
    );
    // 2 used colors hidden: palette - 2 swatches + 1 custom button.
    expect(find.byType(InkResponse), findsNWidgets(palette.length - 1));
  });

  testWidgets('the selected color stays visible even when marked used', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeColorGrid(
          selectedColor: palette[0].toARGB32(),
          onColorSelected: (_) {},
          usedColors: {palette[0].toARGB32()},
        ),
      ),
    );
    // Nothing hidden — the only "used" color is the current selection.
    expect(find.byType(InkResponse), findsNWidgets(palette.length + 1));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('calls onColorSelected when tapping a swatch', (tester) async {
    int? selected;
    await tester.pumpWidget(
      _wrap(
        EmployeeColorGrid(
          selectedColor: palette[0].toARGB32(),
          onColorSelected: (v) => selected = v,
        ),
      ),
    );
    await tester.tap(find.byType(InkResponse).at(1));
    await tester.pump();
    expect(selected, palette[1].toARGB32());
  });

  testWidgets('shows checkmark on the selected swatch', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeColorGrid(
          selectedColor: palette[2].toARGB32(),
          onColorSelected: (_) {},
        ),
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('shows the custom button with add icon', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeColorGrid(
          selectedColor: palette[0].toARGB32(),
          onColorSelected: (_) {},
        ),
      ),
    );
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('a custom selected color appears as its own selected swatch', (
    tester,
  ) async {
    const custom = 0xFF123456;
    await tester.pumpWidget(
      _wrap(
        EmployeeColorGrid(selectedColor: custom, onColorSelected: (_) {}),
      ),
    );
    // Palette swatches + the custom selected swatch + the custom button.
    expect(find.byType(InkResponse), findsNWidgets(palette.length + 2));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
