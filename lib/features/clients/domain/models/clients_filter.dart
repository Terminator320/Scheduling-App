import 'package:flutter/foundation.dart';

import 'package:scheduling/features/clients/domain/models/client_type.dart';

/// Which slice of the client roster the list is showing.
///
/// Sealed so "archived AND commercial" is unexpressible rather than merely
/// unhandled — the chips are mutually exclusive by design.
@immutable
sealed class ClientsFilter {
  const ClientsFilter();
}

class ClientsFilterAll extends ClientsFilter {
  const ClientsFilterAll();

  @override
  bool operator ==(Object other) => other is ClientsFilterAll;

  @override
  int get hashCode => 1;
}

class ClientsFilterType extends ClientsFilter {
  const ClientsFilterType(this.type);
  final ClientType type;

  @override
  bool operator ==(Object other) =>
      other is ClientsFilterType && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

class ClientsFilterArchived extends ClientsFilter {
  const ClientsFilterArchived();

  @override
  bool operator ==(Object other) => other is ClientsFilterArchived;

  @override
  int get hashCode => 0;
}

/// Tapping the already-selected chip clears back to [ClientsFilterAll],
/// mirroring the pre-existing ClientTypeFilterBar behaviour. All three members
/// compare by VALUE, so this never depends on const canonicalization.
ClientsFilter toggledFilter(ClientsFilter current, ClientsFilter tapped) =>
    current == tapped ? const ClientsFilterAll() : tapped;
