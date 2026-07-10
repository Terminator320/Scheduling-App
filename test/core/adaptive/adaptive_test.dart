import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';

Widget _host(TargetPlatform platform, ValueChanged<bool> onBuilt) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: Builder(
      builder: (context) {
        onBuilt(context.isCupertino);
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  testWidgets('isCupertino is true on iOS', (tester) async {
    late bool value;
    await tester.pumpWidget(_host(TargetPlatform.iOS, (v) => value = v));
    expect(value, isTrue);
  });

  testWidgets('isCupertino is true on macOS', (tester) async {
    late bool value;
    await tester.pumpWidget(_host(TargetPlatform.macOS, (v) => value = v));
    expect(value, isTrue);
  });

  testWidgets('isCupertino is false on Android', (tester) async {
    late bool value;
    await tester.pumpWidget(_host(TargetPlatform.android, (v) => value = v));
    expect(value, isFalse);
  });
}
