import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
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

/// The attached client's previous job addresses and last visit, read from the
/// history both hosts already page through.
///
/// Same shape as `watchAssigneeAvailability`: called from `build`, so it
/// re-resolves as the attached client changes, and a pending or failed lookup
/// simply answers nothing rather than blocking the form.
ClientBookingContext watchClientBookingContext(
  WidgetRef ref, {
  required ClientRecord? client,
}) {
  if (client == null || client.id.isEmpty) return _noContext;
  final history = ref.watch(clientJobHistoryProvider(client.id)).value;
  if (history == null || history.isEmpty) return _noContext;
  final seen = <String>{};
  return (
    previousAddresses: [
      for (final visit in history)
        if (visit.address.trim().isNotEmpty && seen.add(visit.address.trim()))
          visit.address.trim(),
    ],
    lastVisitLabel: DateUtilsHelper.formatDayRange(
      history.first.startTime,
      history.first.startTime,
    ),
  );
}
