import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/maps/address_field_filler.dart';

/// Pins which fields `fillAddressControllersFromText` overwrites and which it
/// protects. The distinction is not obvious from the call site — the docstring
/// used to claim it left every manually-entered value intact, while three of
/// the six fields overwrite unconditionally — so the contract is asserted here
/// rather than described.
void main() {
  late TextEditingController address;
  late TextEditingController apt;
  late TextEditingController city;
  late TextEditingController province;
  late TextEditingController postalCode;
  late TextEditingController country;

  setUp(() {
    address = TextEditingController();
    apt = TextEditingController();
    city = TextEditingController();
    province = TextEditingController();
    postalCode = TextEditingController();
    country = TextEditingController();
  });

  tearDown(() {
    for (final c in [address, apt, city, province, postalCode, country]) {
      c.dispose();
    }
  });

  void fill(String raw) => fillAddressControllersFromText(
    raw,
    address: address,
    apt: apt,
    city: city,
    province: province,
    postalCode: postalCode,
    country: country,
  );

  const full = '123 Rue Principale, Montreal, QC H3Z 2Y7, Canada';

  // `AddressParser.parse` only reports a `street` when there is an apt to split
  // out of it — on a plain address it returns null. This function no longer
  // leans on that: it falls back to the raw text and reduces either one through
  // `streetOnly`, because that null is exactly what used to leave the whole
  // picked string sitting in the address box.
  const withApt = '123 Rue Principale, Apt 12, Montreal, QC H3Z 2Y7, Canada';

  // What both fixtures reduce to once the locality is in its own boxes.
  const street = '123 Rue Principale';

  test('fills every empty field from a picked address', () {
    fill(full);
    expect(city.text, 'Montreal');
    expect(province.text, 'QC');
    expect(postalCode.text, 'H3Z 2Y7');
    expect(country.text, 'Canada');
  });

  test('OVERWRITES a stale city, province and postal code', () {
    // The point of picking a suggestion. Keeping the old city beside the new
    // street would be wrong and invisible.
    city.text = 'Laval';
    province.text = 'ON';
    postalCode.text = 'A1A 1A1';

    fill(full);

    expect(city.text, 'Montreal');
    expect(province.text, 'QC');
    expect(postalCode.text, 'H3Z 2Y7');
  });

  test('PROTECTS an apt the user typed', () {
    // A unit number is the one part a suggestion never carries.
    apt.text = '4B';
    fill(full);
    expect(apt.text, '4B');
  });

  test('fills apt when it is empty and the address carries one', () {
    fill(withApt);
    expect(apt.text, '12');
  });

  test('STRIPS the locality the other boxes are about to receive', () {
    // The bug this function had: the street box kept the whole picked string
    // while city/province/postal/country each got a copy of their part, so
    // every locality value was stored twice and the two could drift apart.
    fill(full);
    expect(address.text, street);
    expect(city.text, 'Montreal');
  });

  test('strips it on an apt-bearing address too', () {
    // Different parser path — `parse` reports a street here — same result.
    fill(withApt);
    expect(address.text, street);
    expect(apt.text, '12');
  });

  test('leaves the street controller alone when it already matches', () {
    // Rewriting it would move the caret in a field being edited.
    address.value = const TextEditingValue(
      text: street,
      selection: TextSelection.collapsed(offset: 4),
    );

    fill(withApt);

    expect(address.text, street);
    expect(address.selection.baseOffset, 4);
  });

  test('moves the caret to the end when it does rewrite the street', () {
    address.text = 'something else';
    fill(withApt);
    expect(address.selection.baseOffset, address.text.length);
  });

  test('does not clobber a non-Canada country with the parser default', () {
    country.text = 'France';
    fill('123 Rue Principale, Montreal, QC H3Z 2Y7');
    expect(country.text, 'France');
  });
}
