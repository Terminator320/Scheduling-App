import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/notices/notice_listener.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    // Mirrors main.dart: NoticeListener sits above the Navigator and inserts
    // its banners into the navigator's overlay via the key.
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => NoticeListener(
            navigatorKey: navigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: Text('app-body')),
        ),
      ),
    );
  }

  NoticeService service(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.text('app-body')),
  ).read(noticeServiceProvider);

  testWidgets('close button is a 48px IconButton with a tooltip', (
    tester,
  ) async {
    await pumpApp(tester);
    service(tester).info('hello notice');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('hello notice'), findsOneWidget);
    final closeButton = find.byTooltip('Close');
    expect(closeButton, findsOneWidget);
    final size = tester.getSize(
      find.ancestor(of: closeButton, matching: find.byType(IconButton)),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    await tester.tap(closeButton);
    await tester.pump(); // Start the exit animation (ticker start frame).
    await tester.pump(const Duration(milliseconds: 400)); // Finish it.
    await tester.pump(); // Process the overlay-entry removal.
    expect(find.text('hello notice'), findsNothing);

    // Flush the (now no-op) auto-dismiss timer so the test ends cleanly.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('banner can be swiped up to dismiss', (tester) async {
    await pumpApp(tester);
    service(tester).error('swipe me');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('swipe me'), findsOneWidget);

    await tester.fling(find.text('swipe me'), const Offset(0, -120), 1000);
    await tester.pumpAndSettle();
    expect(find.text('swipe me'), findsNothing);

    // Flush the (now no-op) auto-dismiss timer so the test ends cleanly.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('auto-dismiss timer is preserved', (tester) async {
    await pumpApp(tester);
    service(tester).success('short lived');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('short lived'), findsOneWidget);

    // Non-accessible-navigation duration is 3s; add the exit animation.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('short lived'), findsNothing);
  });
}
