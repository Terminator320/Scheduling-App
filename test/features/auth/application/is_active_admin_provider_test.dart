import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/application/is_active_admin_provider.dart';

void main() {
  ProviderContainer containerFor(Stream<Map<String, dynamic>> doc) {
    final container = ProviderContainer(
      overrides: [currentUserDocProvider.overrideWith((_) => doc)],
    );
    addTearDown(container.dispose);
    // Riverpod 3 auto-disposes an unlistened provider, which can tear it down
    // between this read and the stream's (async) emission.
    container.listen(currentUserDocProvider, (_, _) {});
    return container;
  }

  Future<bool> resolve(Map<String, dynamic> doc) async {
    final container = containerFor(Stream.value(doc));
    await container.read(currentUserDocProvider.future);
    return await Future.value(container.read(isActiveAdminProvider));
  }

  test('an active admin resolves true', () async {
    expect(await resolve({'role': 'admin', 'status': 'active'}), isTrue);
  });

  test('a disabled admin resolves false', () async {
    expect(await resolve({'role': 'admin', 'status': 'disabled'}), isFalse);
  });

  test('an active employee resolves false', () async {
    expect(await resolve({'role': 'employee', 'status': 'active'}), isFalse);
  });

  test('an empty doc resolves false', () async {
    expect(await resolve(const {}), isFalse);
  });

  test('surrounding whitespace does not defeat the match', () async {
    expect(await resolve({'role': ' admin ', 'status': ' active '}), isTrue);
  });

  test('an UNSETTLED doc fails CLOSED', () {
    // The whole point: "we do not know yet" must never read as "admin".
    final container = containerFor(const Stream.empty());
    expect(container.read(isActiveAdminProvider), isFalse);
  });
}
