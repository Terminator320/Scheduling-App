import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/features/clients/application/client_form_controller.dart';
import 'package:scheduling/features/clients/domain/clients_failure.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';

/// Archive / delete handlers shared by the clients list and the client detail.
///
/// Both surfaces must agree on the notices, the CLI-ARCH / CLI-DEL log tags and
/// the confirm copy, so the flow lives here once rather than being copied into
/// each host — two copies of a rule whose answers must match is exactly the
/// drift this codebase keeps paying for.
mixin ClientActionsHost<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Called after a successful archive / un-archive. Deliberately separate
  /// from [onClientDeleted]: the list just refreshes for both, but the detail
  /// view must STAY OPEN here (so it can offer Unarchive) and dismiss there.
  /// One shared hook could not express that difference.
  void onClientArchived(ClientRecord client, {required bool archived});

  /// Called after a successful delete, once the record is gone.
  void onClientDeleted(ClientRecord client);

  /// Toggles [client]'s archived state.
  Future<void> archiveClient(ClientRecord client) async {
    final next = !client.archived;
    if (guardedOffline(
      context,
      ref,
      intro: context.l10n.error_introArchiveClient,
      tag: 'CLI-ARCH',
    )) {
      return;
    }

    final notices = ref.read(noticeServiceProvider);
    final outcome = await ref
        .read(clientFormControllerProvider.notifier)
        .setArchived(client.id, archived: next);
    if (!mounted) return;
    switch (outcome) {
      // A write the reentrancy guard skipped: nothing committed and nothing
      // failed, so this surfaces nothing at all.
      case ClientArchiveBusy():
        return;
      case ClientArchived(:final archived):
        notices.success(
          archived
              ? context.l10n.clients_archivedNotice(client.displayName)
              : context.l10n.clients_unarchivedNotice(client.displayName),
        );
        onClientArchived(client, archived: archived);
      case ClientArchiveFailed(:final error):
        notices.error(
          composeErrorNotice(
            context,
            intro: context.l10n.error_introArchiveClient,
            tag: 'CLI-ARCH',
            error: error,
          ),
        );
    }
  }

  /// Confirms, then deletes [client]. The server refuses a client that still
  /// has appointments; [ClientsFailureHasHistory] is what says so usefully.
  Future<void> confirmDeleteClient(ClientRecord client) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.clients_deleteTitle,
      message: context.l10n.clients_deleteMessage(client.displayName),
      confirmLabel: context.l10n.common_delete,
    );
    if (!confirmed || !mounted) return;
    if (guardedOffline(
      context,
      ref,
      intro: context.l10n.error_introDeleteClient,
      tag: 'CLI-DEL',
    )) {
      return;
    }

    final notices = ref.read(noticeServiceProvider);
    final outcome = await ref
        .read(clientFormControllerProvider.notifier)
        .deleteClient(client.id);
    if (!mounted) return;
    switch (outcome) {
      case ClientDeleted():
        notices.success(context.l10n.clients_deletedNotice(client.displayName));
        onClientDeleted(client);
      case ClientDeleteFailed(:final error):
        // The typed branch runs first: "archive it instead" is actionable,
        // where the generic cause+tag notice would not be.
        if (error is ClientsFailure) {
          notices.error(error.toLocalizedMessage(context));
          return;
        }
        notices.error(
          composeErrorNotice(
            context,
            intro: context.l10n.error_introDeleteClient,
            tag: 'CLI-DEL',
            error: error,
          ),
        );
    }
  }
}
