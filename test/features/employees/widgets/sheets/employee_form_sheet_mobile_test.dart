import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/sheets/employee_form_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

const _employee = EmployeeRecord(
  id: 'e1',
  name: 'Alexandria Beaumont',
  email: 'alexandria@example.com',
  phone: '555-0101',
  status: 'active',
  uid: 'uid1',
  color: Color(0xFF6366F1),
);

Widget _wrap(Widget child) => ProviderScope(
  child: ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: 2,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: child),
    ),
  ),
);

void main() {
  testWidgets(
    'employee form sheet does not overflow at 2x text on phone width',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const EmployeeFormSheet(employee: _employee)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
