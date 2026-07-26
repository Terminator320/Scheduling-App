import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

void main() {
  const employees = [
    EmployeeRecord(
      id: 'e1',
      name: 'Zoé Bélanger',
      email: 'zoe@shop.ca',
      phone: '514-555-0100',
    ),
    EmployeeRecord(
      id: 'e2',
      name: 'John Smith',
      email: 'john@shop.ca',
      phone: '438-555-0199',
    ),
  ];

  Future<List<EmployeeRecord>> filter(String query) async {
    final container = ProviderContainer(
      overrides: [
        allUsersStreamProvider.overrideWith((ref) => Stream.value(employees)),
      ],
    );
    // Keep the subscription alive so Stream.value can emit, then close it before
    // the container to avoid the Riverpod 3 teardown race on StreamProvider futures.
    final sub = container.listen(allUsersStreamProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final result = container.read(filteredEmployeesProvider(query));
    sub.close();
    container.dispose();
    return result;
  }

  test('matches an accented name when typing without the accent', () async {
    final results = await filter('zoe');
    expect(results.map((e) => e.id), ['e1']);
  });

  test('matches a digits-only phone when the query is formatted', () async {
    final results = await filter('(514) 555');
    expect(results.map((e) => e.id), ['e1']);
  });

  test('matches on email', () async {
    final results = await filter('john@shop');
    expect(results.map((e) => e.id), ['e2']);
  });

  test('a blank query returns everyone', () async {
    final results = await filter('   ');
    expect(results.length, 2);
  });

  test('an unrelated query matches no one', () async {
    final results = await filter('Xavier');
    expect(results, isEmpty);
  });
}
