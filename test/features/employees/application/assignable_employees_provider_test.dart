import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';

EmployeeRecord _employee(String id, JobTitle jobTitle) => EmployeeRecord(
  id: id,
  name: 'Person $id',
  email: '$id@example.com',
  status: 'active',
  jobTitle: jobTitle,
);

/// The listen keeps the autoDispose state alive across the settle and the read.
ProviderContainer _containerWith(List<EmployeeRecord> employees) {
  final container =
      ProviderContainer(
        overrides: [
          employeesStreamProvider.overrideWith((ref) => Stream.value(employees)),
        ],
      )..listen(assignableEmployeesProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a dispatcher is not offered as an assignee', () async {
    final container = _containerWith([
      _employee('e1', JobTitle.technician),
      _employee('e2', JobTitle.dispatcher),
      _employee('e3', JobTitle.leadTech),
    ]);

    await container.read(employeesStreamProvider.future);
    final assignable = container.read(assignableEmployeesProvider).requireValue;

    expect(assignable.map((e) => e.id), ['e1', 'e3']);
  });

  test('a title that was never picked stays assignable', () async {
    final container = _containerWith([
      _employee('e1', JobTitle.unset),
      _employee('e2', JobTitle.apprentice),
    ]);

    await container.read(employeesStreamProvider.future);
    final assignable = container.read(assignableEmployeesProvider).requireValue;

    expect(assignable.map((e) => e.id), ['e1', 'e2']);
  });

  test('loading and error states pass straight through', () async {
    final container =
        ProviderContainer(
          overrides: [
            employeesStreamProvider.overrideWith(
              (ref) => Stream<List<EmployeeRecord>>.error(StateError('denied')),
            ),
          ],
        )..listen(assignableEmployeesProvider, (_, _) {});
    addTearDown(container.dispose);

    expect(container.read(assignableEmployeesProvider).isLoading, isTrue);
    await expectLater(
      container.read(employeesStreamProvider.future),
      throwsStateError,
    );
    expect(container.read(assignableEmployeesProvider).hasError, isTrue);
  });
}
