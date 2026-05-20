import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';

double _shakeDx(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byType(AnimatedFormFieldWrapper),
          matching: find.byType(Transform),
        )
        .first,
  );
  return transform.transform.getTranslation().x;
}

Widget _host({required bool hasError, bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedFormFieldWrapper(
        hasError: hasError,
        child: const SizedBox(width: 120, height: 40),
      ),
    ),
  );
}

void main() {
  testWidgets('does not shake on first build, even with an error', (
    tester,
  ) async {
    await tester.pumpWidget(_host(hasError: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_shakeDx(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shakes when hasError flips false to true, then settles', (
    tester,
  ) async {
    await tester.pumpWidget(_host(hasError: false));
    await tester.pumpWidget(_host(hasError: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_shakeDx(tester), isNot(0));

    await tester.pumpAndSettle();
    expect(_shakeDx(tester).abs(), lessThan(0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion disables the shake', (tester) async {
    await tester.pumpWidget(_host(hasError: false, disableAnimations: true));
    await tester.pumpWidget(_host(hasError: true, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_shakeDx(tester), 0);
  });

  testWidgets('keyboard focus survives the shake (no remount)', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    Widget host({required bool hasError}) => MaterialApp(
      home: Scaffold(
        body: AnimatedFormFieldWrapper(
          hasError: hasError,
          child: TextField(controller: controller, focusNode: focusNode),
        ),
      ),
    );

    await tester.pumpWidget(host(hasError: false));
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.pumpWidget(host(hasError: true));
    await tester.pumpAndSettle();

    expect(focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
