import 'package:flutter/widgets.dart';
import 'package:scheduling/core/analytics/analytics_events.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_prefill.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';

/// The add-client → book-a-job flow, in one place.
Future<void> runAddClientFlow(BuildContext context) async {
  final result = await showAddClientSheet(
    context,
    analyticsSource: AnalyticsSources.clientsTab,
  );
  if (result == null || result.next != AddClientNext.bookJob) return;
  if (!context.mounted) return;
  await showAddEventPopup(
    context,
    prefill: AppointmentPrefill(client: result.client),
  );
}
