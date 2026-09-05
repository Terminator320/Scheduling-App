import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

/// A client this admin booked recently, built from appointments the app has
/// already read. Deliberately NOT a `ClientRecord`: it carries only what an
/// appointment denormalizes, so showing recents costs no client reads at all.
typedef RecentClient = ({
  String clientId,
  String name,
  String phone,
  String address,
});

/// Newest-first, one entry per client, capped.
List<RecentClient> recentClientsFrom(
  List<AppointmentRecord> bookings, {
  int limit = 40,
}) {
  final seen = <String>{};
  final out = <RecentClient>[];
  for (final booking in bookings) {
    if (booking.clientId.isEmpty) continue;
    if (!seen.add(booking.clientId)) continue;
    out.add((
      clientId: booking.clientId,
      name: booking.clientName,
      phone: booking.clientPhone,
      address: booking.address,
    ));
    if (out.length >= limit) break;
  }
  return out;
}

/// The local filter the picker applies while the query is too short to send.
bool matchesDigits(RecentClient recent, String digits) {
  if (digits.isEmpty) return true;
  return ClientSearchPolicy.digitsOnly(recent.phone).contains(digits);
}
