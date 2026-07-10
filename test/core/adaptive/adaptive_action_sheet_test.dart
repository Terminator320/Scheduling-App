import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _host(TargetPlatform platform, {String? title}) => MaterialApp(
  theme: ThemeData(platform: platform),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showAdaptiveActionSheet<int>(
            context,
            title: title,
            actions: const [
              AdaptiveSheetAction(
                value: 1,
                label: 'Camera',
                icon: Icons.camera_alt,
              ),
              AdaptiveSheetAction(
                value: 2,
                label: 'Gallery',
                icon: Icons.photo,
              ),
            ],
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows CupertinoActionSheet on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows Material bottom sheet with ListTiles on Android', (
    tester,
  ) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders title header in the Android sheet', (tester) async {
    await tester.pumpWidget(
      _host(TargetPlatform.android, title: 'Choose source'),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Choose source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
