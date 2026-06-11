import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/widgets/fields/client_address_section.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  late TextEditingController address;
  late TextEditingController apt;
  late TextEditingController city;
  late TextEditingController province;
  late TextEditingController postalCode;
  late TextEditingController country;

  setUp(() {
    address = TextEditingController(text: '1 Main St');
    apt = TextEditingController(text: '4B');
    city = TextEditingController(text: 'Toronto');
    province = TextEditingController(text: 'ON');
    postalCode = TextEditingController(text: 'M1M 1M1');
    country = TextEditingController(text: 'Canada');
  });

  tearDown(() {
    address.dispose();
    apt.dispose();
    city.dispose();
    province.dispose();
    postalCode.dispose();
    country.dispose();
  });

  Widget section({VoidCallback? onErrorCleared}) => ClientAddressSection(
    addressController: address,
    aptController: apt,
    cityController: city,
    provinceController: province,
    postalCodeController: postalCode,
    countryController: country,
    isRequired: true,
    onAddressErrorCleared: onErrorCleared ?? () {},
  );

  testWidgets('Clear address empties every address field', (tester) async {
    var errorCleared = false;
    await tester.pumpWidget(
      _wrap(section(onErrorCleared: () => errorCleared = true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear address'));
    await tester.pumpAndSettle();

    expect(address.text, isEmpty);
    expect(apt.text, isEmpty);
    expect(city.text, isEmpty);
    expect(province.text, isEmpty);
    expect(postalCode.text, isEmpty);
    expect(country.text, isEmpty);
    expect(errorCleared, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear address hides itself once everything is empty', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(section()));
    await tester.pumpAndSettle();
    expect(find.text('Clear address'), findsOneWidget);

    await tester.tap(find.text('Clear address'));
    await tester.pumpAndSettle();

    expect(find.text('Clear address'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear address is hidden when the block starts empty', (
    tester,
  ) async {
    for (final c in [address, apt, city, province, postalCode, country]) {
      c.clear();
    }
    await tester.pumpWidget(_wrap(section()));
    await tester.pumpAndSettle();

    expect(find.text('Clear address'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
