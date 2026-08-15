import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/storage/secure_storage_service.dart';

/// A substring match on an exception message is the most fragile predicate
/// shape there is: the null-message case must answer `false` rather than throw,
/// and a non-platform error must never be read as a locked keychain.
void main() {
  group('isKeychainLockedError', () {
    test('a -25308 PlatformException is a locked keychain', () {
      expect(
        isKeychainLockedError(
          PlatformException(
            code: 'Unexpected security result code',
            message: 'Code: -25308, Message: interactionNotAllowed',
          ),
        ),
        isTrue,
      );
    });

    test('a PlatformException with no message is not one', () {
      expect(
        isKeychainLockedError(PlatformException(code: 'Unexpected')),
        isFalse,
      );
    });

    test('another keychain status code is not one', () {
      expect(
        isKeychainLockedError(
          PlatformException(
            code: 'Unexpected security result code',
            message: 'Code: -25300, Message: itemNotFound',
          ),
        ),
        isFalse,
      );
    });

    test('a plain exception carrying -25308 is not one', () {
      expect(isKeychainLockedError(Exception('-25308')), isFalse);
    });
  });
}
