import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:scheduling/core/permissions/media_permission_service.dart';

void main() {
  test('camera request maps the granted status', () async {
    final service = MediaPermissionService(
      requestCamera: () async => PermissionStatus.granted,
    );

    expect(await service.ensureCamera(), MediaPermissionResult.granted);
  });

  test('camera request failure degrades to denied', () async {
    final service = MediaPermissionService(
      requestCamera: () async => throw StateError('camera unavailable'),
    );

    expect(await service.ensureCamera(), MediaPermissionResult.denied);
  });

  test('photo add-only request failure degrades to denied', () async {
    final service = MediaPermissionService(
      requestPhotoAddOnly: () async => throw StateError('photos unavailable'),
    );

    expect(await service.ensurePhotoAddOnly(), MediaPermissionResult.denied);
  });
}
