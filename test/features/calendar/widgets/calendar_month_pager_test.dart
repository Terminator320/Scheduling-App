import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_pager.dart';
import 'package:scheduling/l10n/l10n.dart';

final _today = DateTime(2026, 5, 16);

/// Drives the pager the way the screen does: the parent owns `month` and
/// updates it from `onMonthChanged`.
class _Host extends StatefulWidget {
  const _Host({required this.onMonthChanged, super.key});

  final ValueChanged<DateTime> onMonthChanged;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  DateTime _month = DateTime(2026, 5);

  void jumpTo(DateTime month) => setState(() => _month = month);

  @override
  Widget build(BuildContext context) => CalendarMonthPager(
    month: _month,
    selectedDay: _today,
    today: _today,
    onDaySelected: (_) {},
    onMonthChanged: (m) {
      setState(() => _month = m);
      widget.onMonthChanged(m);
    },
    dotColorsFor: (_) => const [],
    countFor: (_) => 0,
  );
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  testWidgets('swiping left advances a month', (tester) async {
    final months = <DateTime>[];
    await tester.pumpWidget(
      _wrap(_Host(onMonthChanged: months.add)),
    );
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(months, isNotEmpty);
    expect(months.last.year, 2026);
    expect(months.last.month, 6);
  });

  testWidgets('swiping right goes back a month', (tester) async {
    final months = <DateTime>[];
    await tester.pumpWidget(
      _wrap(_Host(onMonthChanged: months.add)),
    );
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();

    expect(months.last.month, 4);
  });

  testWidgets('paging across a year boundary lands on January', (
    tester,
  ) async {
    final months = <DateTime>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _wrap(_Host(key: key, onMonthChanged: months.add)),
    );
    await tester.pumpAndSettle();

    key.currentState!.jumpTo(DateTime(2026, 12));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(months.last.year, 2027);
    expect(months.last.month, 1);
  });

  testWidgets('an external month change moves the pager without a callback', (
    tester,
  ) async {
    final months = <DateTime>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _wrap(_Host(key: key, onMonthChanged: months.add)),
    );
    await tester.pumpAndSettle();

    // The month/year picker and the Today pill drive the month this way.
    key.currentState!.jumpTo(DateTime(2026, 9));
    await tester.pumpAndSettle();

    expect(months, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
