import 'package:flutter/material.dart';

import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';

/// Shows a delete confirmation for appointments.
///
/// One day of a multi-day RUN and one occurrence of a repeat both offer 'this
/// one only' or 'this and the ones after it', in their own words; a null result
/// means the user cancelled.
Future<SeriesScopeChoice?> showDeleteAppointmentDialog(
  BuildContext context, {
  required bool isSeries,
  bool isRun = false,
}) async {
  final l = context.l10n;
  if (!isSeries) {
    final confirmed = await showConfirmDialog(
      context,
      title: l.calendar_deleteAppointment,
      message: l.calendar_areYouSureYouWantToDeleteThisJob,
      confirmLabel: l.common_delete,
    );
    return confirmed ? SeriesScopeChoice.thisOnly : null;
  }
  return await showSeriesScopeDialog(
    context,
    title: l.calendar_deleteAppointment,
    thisOnlyLabel: isRun
        ? l.calendar_deleteThisDayOnly
        : l.calendar_deleteThisVisitOnly,
    thisAndFutureLabel: isRun
        ? l.calendar_deleteThisAndFollowingDays
        : l.calendar_deleteThisAndFutureVisits,
    // The scope IS the verb here, so this site keeps its own copy rather than
    // switching the label on the selection.
    primaryLabelFor: (_) => l.calendar_deleteAppointment,
    thisOnlyDetail: isRun
        ? l.calendar_deleteRunScopeMessage
        : l.calendar_deleteSeriesScopeMessage,
    destructive: true,
  );
}
