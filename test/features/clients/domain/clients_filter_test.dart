import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';

void main() {
  test('type and archived are distinct states', () {
    const archived = ClientsFilterArchived();
    const typed = ClientsFilterType(ClientType.commercial);

    expect(archived, isNot(equals(typed)));
    expect(const ClientsFilterAll(), isNot(equals(archived)));
    expect(const ClientsFilterAll(), isNot(equals(typed)));
  });

  test('two filters of the same type compare equal', () {
    expect(
      const ClientsFilterType(ClientType.commercial),
      equals(const ClientsFilterType(ClientType.commercial)),
    );
    expect(
      const ClientsFilterType(ClientType.commercial),
      isNot(equals(const ClientsFilterType(ClientType.residential))),
    );
  });

  test('tapping the active chip clears back to All', () {
    expect(
      toggledFilter(
        const ClientsFilterArchived(),
        const ClientsFilterArchived(),
      ),
      isA<ClientsFilterAll>(),
    );
    expect(
      toggledFilter(
        const ClientsFilterType(ClientType.commercial),
        const ClientsFilterType(ClientType.commercial),
      ),
      isA<ClientsFilterAll>(),
    );
  });

  test('tapping an inactive chip selects it', () {
    expect(
      toggledFilter(const ClientsFilterAll(), const ClientsFilterArchived()),
      isA<ClientsFilterArchived>(),
    );
    // Switching straight from one chip to another, not via All.
    expect(
      toggledFilter(
        const ClientsFilterArchived(),
        const ClientsFilterType(ClientType.commercial),
      ),
      isA<ClientsFilterType>(),
    );
  });
}
