import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/shared/widgets/primitives/quick_action_button.dart';

void main() {
  testWidgets('QuickActionButton label supports up to two lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            child: QuickActionButton(
              icon: Icons.directions_outlined,
              label: 'Very Long Directions Label',
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Very Long Directions Label'));
    expect(text.maxLines, 2);
  });
}
