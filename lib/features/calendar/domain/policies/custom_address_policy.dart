import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';

/// Whether a job at [appointmentAddress] used its own address rather than
/// [client]'s — the flag the form's address pill reads.
bool usesCustomAddress({
  required String appointmentAddress,
  required ClientRecord client,
}) =>
    client.noFixedAddress ||
    AddressParser.toCanonical(appointmentAddress) !=
        AddressParser.toCanonical(client.fullAddress);
