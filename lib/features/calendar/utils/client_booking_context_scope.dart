import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/appointment_history_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// What the WHO section knows about the attached client's earlier jobs.
typedef ClientBookingContext = ({
  List<String> previousAddresses,
  String? lastVisitLabel,
});

const ClientBookingContext _noContext = (
  previousAddresses: [],
  lastVisitLabel: null,
);

/// How many distinct addresses the WHO section will offer. A property manager
/// with thirty units would otherwise build thirty eager rows inside a form
/// sheet; "Search for another address" is the way past this.
const int kBookingPreviousAddressLimit = 8;

/// The attached client's previous job addresses and last visit.
///
/// Same shape as `watchAssigneeAvailability`: called from `build`, so it
/// re-resolves as the attached client changes, and a pending or failed lookup
/// simply answers nothing rather than blocking the form.
ClientBookingContext watchClientBookingContext(
  WidgetRef ref, {
  required ClientRecord? client,
}) {
  if (client == null || client.id.isEmpty) return _noContext;
  final history = ref.watch(clientBookingHistoryProvider(client.id)).value;
  if (history == null || history.isEmpty) return _noContext;
  // Watched for the rebuild when the day turns; the cut itself is an INSTANT,
  // because a visit earlier this morning is a past one.
  ref.watch(currentDayProvider);
  return clientBookingContextOf(history, now: DateTime.now());
}

/// [watchClientBookingContext]'s pure half.
ClientBookingContext clientBookingContextOf(
  List<AppointmentRecord> history, {
  required DateTime now,
}) {
  final seen = <String>{};
  final addresses = <String>[];
  for (final visit in history) {
    if (addresses.length >= kBookingPreviousAddressLimit) break;
    final address = visit.address.trim();
    if (address.isNotEmpty && seen.add(address)) addresses.add(address);
  }
  // The scan carries no time filter, so the newest document by `startTime` is
  // routinely a booking that has not happened yet.
  final lastVisit = history
      .where((visit) => !visit.startTime.isAfter(now))
      .firstOrNull;
  final value = (
    previousAddresses: addresses,
    lastVisitLabel: lastVisit == null
        ? null
        : DateUtilsHelper.formatDayRange(
            lastVisit.startTime,
            lastVisit.startTime,
          ),
  );
  return value;
}
