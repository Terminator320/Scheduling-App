import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// Whether the UI should OFFER delete for [client].
///
/// Advisory only — the `deleteClient` callable re-checks with a live count()
/// aggregate and is the real boundary. This exists so the swipe never offers
/// an action the server will refuse.
///
/// `jobCount` is lazily backfilled and renders nothing until it exists, so a
/// client with real history can legitimately carry no count. `null == 0` is
/// false, which withholds the action: missing means unknown, and unknown
/// withholds.
bool canDeleteClient(ClientRecord client) => client.jobCount == 0;
