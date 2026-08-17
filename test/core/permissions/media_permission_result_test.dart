// Pins how a raw PermissionStatus is bucketed. Both interesting cases fail
// SILENTLY if they regress: iOS `limited` is a usable grant that would
// otherwise read as a refusal, and `restricted` can never be re-prompted, so
// treating it as plain denied loops the user through a dialog that no-ops.

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:scheduling/core/permissions/media_permission_service.dart';

void main() {
  test('granted is granted', () {
    expect(
      mediaPermissionResultOf(PermissionStatus.granted),
      MediaPermissionResult.granted,
    );
  });

  test('iOS "selected photos" (limited) counts as granted', () {
    expect(
      mediaPermissionResultOf(PermissionStatus.limited),
      MediaPermissionResult.granted,
    );
  });

  test('restricted is permanent, not a re-promptable denial', () {
    // Parental controls / MDM. Re-asking can never succeed, so the caller has
    // to send them to Settings instead.
    expect(
      mediaPermissionResultOf(PermissionStatus.restricted),
      MediaPermissionResult.permanentlyDenied,
    );
    expect(
      mediaPermissionResultOf(PermissionStatus.permanentlyDenied),
      MediaPermissionResult.permanentlyDenied,
    );
  });

  test('a plain denial stays re-promptable', () {
    expect(
      mediaPermissionResultOf(PermissionStatus.denied),
      MediaPermissionResult.denied,
    );
    expect(
      mediaPermissionResultOf(PermissionStatus.provisional),
      MediaPermissionResult.denied,
    );
  });
}
