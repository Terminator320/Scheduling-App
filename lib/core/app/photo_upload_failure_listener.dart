import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/error_snack_bar.dart';

/// Surfaces a background photo-upload failure, wherever the user happens to be.
///
/// Photos upload AFTER the appointment save returns, so the sheet that started
/// the upload is long gone by the time one fails — which is why this is not the
/// edit sheet's job, and why it lived on the calendar screen. It is not a
/// calendar concern either: it belongs to the session, so it sits here beside
/// `AppSyncListeners` and wraps whichever screen hosts it.
///
/// **This is one of the three sanctioned `SnackBar` sites** (see
/// `.claude/rules/frontend.md`), not a notice: the message carries an action
/// that reopens the appointment, and the notice surface has no action slot.
/// It builds that bar through `errorSnackBar` rather than hand-rolling the
/// `errorContainer` row.
class PhotoUploadFailureListener extends ConsumerStatefulWidget {
  const PhotoUploadFailureListener({
    required this.child,
    super.key,
    this.showActions = false,
  });

  final Widget child;

  /// The host's resolved role, passed to `showEventDetails` when the Open
  /// action reopens the job. Defaults CLOSED, like every appointment surface.
  final bool showActions;

  @override
  ConsumerState<PhotoUploadFailureListener> createState() =>
      _PhotoUploadFailureListenerState();
}

class _PhotoUploadFailureListenerState
    extends ConsumerState<PhotoUploadFailureListener> {
  late final PhotoUploadNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(photoUploadNotifierProvider)
      ..latestFailure.addListener(_onFailure);
  }

  @override
  void dispose() {
    _notifier.latestFailure.removeListener(_onFailure);
    super.dispose();
  }

  void _onFailure() {
    final failure = _notifier.latestFailure.value;
    if (failure == null || !mounted) return;
    final appointmentId = failure.appointmentId;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      errorSnackBar(
        context,
        context.l10n.calendar_photoUploadFailedSnackbar,
        action: SnackBarAction(
          label: context.l10n.calendar_open,
          textColor: scheme.onErrorContainer,
          onPressed: () async {
            final appointment = await ref
                .read(appointmentsRepositoryProvider)
                .getAppointmentById(appointmentId);
            if (!mounted || appointment == null) return;
            await showEventDetails(
              context,
              appointment,
              showActions: widget.showActions,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
