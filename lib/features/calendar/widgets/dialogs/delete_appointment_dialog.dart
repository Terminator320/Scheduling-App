import 'package:flutter/material.dart';

import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';

/// Delete confirmation for appointments; a repeating visit offers 'this only' or 'this and future' (null = cancelled).
Future<SeriesScopeChoice?> showDeleteAppointmentDialog(
  BuildContext context, {
  required bool isSeries,
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
  return showSeriesScopeDialog(
    context,
    title: l.calendar_deleteAppointment,
    message: l.calendar_deleteSeriesScopeMessage,
    thisOnlyLabel: l.calendar_deleteThisVisitOnly,
    thisAndFutureLabel: l.calendar_deleteThisAndFutureVisits,
    destructive: true,
  );
}
