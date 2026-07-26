import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// P9: derived lookup maps must return the *identical* previous instance for
/// content-equal emissions, so Provider skips notifying the whole calendar.
void main() {
  test('map providers keep the same instance for content-equal emissions', () async {
    final controller = StreamController<List<EmployeeRecord>>();
    addTearDown(controller.close);
    final container = ProviderContainer(
      overrides: [
        allUsersStreamProvider.overrideWith((ref) => controller.stream),
      ],
    );

    var colorNotifications = 0;
    final colorSub = container.listen(
      employeeColorMapProvider,
      (_, _) => colorNotifications++,
    );

    controller.add(const [EmployeeRecord(id: 'e1', name: 'Zoé')]);
    await Future<void>.delayed(Duration.zero);
    final firstColors = container.read(employeeColorMapProvider);
    final firstNames = container.read(employeeNameMapProvider);
    expect(firstColors, isNotEmpty);
    expect(colorNotifications, 1);

    // Same content, fresh list + record instances (e.g. a phone edit
    // elsewhere re-emitted the stream).
    controller.add([const EmployeeRecord(id: 'e1', name: 'Zoé')]);
    await Future<void>.delayed(Duration.zero);
    expect(
      identical(firstColors, container.read(employeeColorMapProvider)),
      isTrue,
    );
    expect(
      identical(firstNames, container.read(employeeNameMapProvider)),
      isTrue,
    );
    expect(colorNotifications, 1, reason: 'unchanged map must not notify');

    // Changed content still produces (and notifies with) a new map.
    controller.add(const [
      EmployeeRecord(id: 'e1', name: 'Zoé', color: Color(0xFF112233)),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(
      identical(firstColors, container.read(employeeColorMapProvider)),
      isFalse,
    );
    expect(colorNotifications, 2);

    // Close in order (subscription before container) to avoid the Riverpod 3
    // teardown race on StreamProvider futures.
    colorSub.close();
    container.dispose();
  });
}
