import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_delete_policy.dart';

ClientRecord clientWith(int? jobCount) =>
    ClientRecord.fromMap('c1', {'name': 'Acme'}).copyWith(jobCount: jobCount);

void main() {
  test('a client with no jobs can be deleted', () {
    expect(canDeleteClient(clientWith(0)), isTrue);
  });

  test('a client with jobs cannot be deleted', () {
    expect(canDeleteClient(clientWith(3)), isFalse);
  });

  test('an unknown job count blocks deletion', () {
    // jobCount is lazily backfilled, so null means "not counted yet", NOT
    // zero. Treating it as zero would offer delete in exactly the case the
    // gate exists to prevent.
    expect(canDeleteClient(clientWith(null)), isFalse);
  });
}
