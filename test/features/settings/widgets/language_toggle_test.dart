import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('language buttons meet the 44px minimum tap target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(LanguageToggle(currentCode: 'en', onChanged: (_) {})),
    );

    for (final label in const ['EN', 'FR']) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(size.width, greaterThanOrEqualTo(44), reason: '$label width');
      expect(size.height, greaterThanOrEqualTo(44), reason: '$label height');
    }
  });

  testWidgets('tapping FR reports the new language code', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(LanguageToggle(currentCode: 'en', onChanged: (c) => selected = c)),
    );

    await tester.tap(find.text('FR'));
    expect(selected, 'fr');
  });

  testWidgets('tapping the already-selected language reports no change', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(LanguageToggle(currentCode: 'fr', onChanged: (c) => selected = c)),
    );

    await tester.tap(find.text('FR'));
    expect(selected, isNull);
  });

  testWidgets('buttons expose button + selected semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(LanguageToggle(currentCode: 'fr', onChanged: (_) {})),
    );

    expect(
      tester.getSemantics(find.text('FR')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('EN')),
      isSemantics(isButton: true, isSelected: false),
    );
    handle.dispose();
  });
}
