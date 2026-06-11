import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const store = ContactLinkStore();

  test('returns null for a client that was never saved', () async {
    expect(await store.contactIdFor('c1'), isNull);
  });

  test('links and reads back a contact id', () async {
    await store.link('c1', 'native-42');
    expect(await store.contactIdFor('c1'), 'native-42');
  });

  test('links are isolated per client', () async {
    await store.link('c1', 'native-1');
    await store.link('c2', 'native-2');
    expect(await store.contactIdFor('c1'), 'native-1');
    expect(await store.contactIdFor('c2'), 'native-2');
  });

  test('unlink drops the stored id', () async {
    await store.link('c1', 'native-42');
    await store.unlink('c1');
    expect(await store.contactIdFor('c1'), isNull);
  });
}
