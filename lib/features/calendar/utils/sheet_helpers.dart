import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_prefill.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/sheets/add_appointment_sheet.dart';
import 'package:scheduling/features/calendar/widgets/sheets/details_edit_sheet.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';

const _kSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.rSheet)),
);

Future<AppointmentRecord?> showAddEventPopup(
  BuildContext context, {
  DateTime? initialDate,
  AppointmentPrefill? prefill,
}) {
  return showAppBottomSheet<AppointmentRecord>(
    context,
    shape: _kSheetShape,
    builder: (_) => AddEventSheet(initialDate: initialDate, prefill: prefill),
  );
}

/// Opens the appointment detail sheet with explicit action visibility.
///
/// [analyticsSource] is REQUIRED rather than defaulted: this sheet is reachable
/// from ten surfaces, and which one a person came from is the whole answer to
/// "how do people actually get to a job?". A default would silently attribute a
/// new call site to whichever surface happened to be the default.
Future<void> showEventDetails(
  BuildContext context,
  AppointmentRecord a, {
  required bool showActions,
  required String analyticsSource,
}) async {
  final result = await showAppBottomSheet<Object?>(
    context,
    shape: _kSheetShape,
    builder: (_) => EventDetailsSheet(
      appointment: a,
      showActions: showActions,
      analyticsSource: analyticsSource,
    ),
  );
  if (result is! AppointmentPrefill || !context.mounted) return;
  await showAddEventPopup(context, prefill: result);
}
