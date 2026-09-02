import 'package:flutter/widgets.dart';

import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';

/// The add-client → book-a-job flow, in one place.
///
/// The Clients tab's FAB and the list's empty-state button both open the
/// add-client sheet and, when it resolves with "book a job", carry the new
/// client straight into the appointment form. Sequential, never stacked: the
/// add-client sheet has already popped before the booking sheet opens.
Future<void> runAddClientFlow(BuildContext context) async {
  final result = await showAddClientSheet(context);
  if (result == null || result.next != AddClientNext.bookJob) return;
  if (!context.mounted) return;
  await showAddEventPopup(context, initialClient: result.client);
}
