// test/user_status_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/user_status_chip.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('UserStatusChip renders Active label', (tester) async {
    await tester.pumpWidget(
      _wrap(const UserStatusChip(status: UserStatus.active)),
    );
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('UserStatusChip renders Invited label', (tester) async {
    await tester.pumpWidget(
      _wrap(const UserStatusChip(status: UserStatus.invited)),
    );
    expect(find.text('Invited'), findsOneWidget);
  });

  testWidgets('UserStatusChip renders Disabled label', (tester) async {
    await tester.pumpWidget(
      _wrap(const UserStatusChip(status: UserStatus.disabled)),
    );
    expect(find.text('Disabled'), findsOneWidget);
  });

  test('UserStatus.fromRaw maps stored status strings', () {
    expect(UserStatus.fromRaw('active'), UserStatus.active);
    expect(UserStatus.fromRaw('disabled'), UserStatus.disabled);
    expect(UserStatus.fromRaw('invited'), UserStatus.invited);
    // An unredeemed invite may carry an empty/unknown status — treat as invited.
    expect(UserStatus.fromRaw(''), UserStatus.invited);
    expect(UserStatus.fromRaw('whatever'), UserStatus.invited);
  });
}
