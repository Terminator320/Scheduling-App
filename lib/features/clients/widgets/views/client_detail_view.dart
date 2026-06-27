import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/views/client_edit_form.dart';
import 'package:scheduling/features/clients/widgets/views/client_view_body.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// Coordinator for the client detail screen: toggles between the read-only
/// [ClientDetailViewBody] and the editable [ClientEditForm], and owns the
/// delete flow (shared by both modes).
class ClientDetailView extends ConsumerStatefulWidget {
  const ClientDetailView({
    required this.client,
    super.key,
    this.scrollController,
    this.showHandle = false,
    this.bottomPadding = 24,
    this.onDeleted,
  });

  final ClientRecord client;
  final ScrollController? scrollController;
  final bool showHandle;
  final double bottomPadding;

  /// Called after a successful delete so a host that keeps this view mounted
  /// (the split-layout detail pane) can clear the now-deleted selection.
  /// In sheet mode the sheet pops itself instead.
  final VoidCallback? onDeleted;

  @override
  ConsumerState<ClientDetailView> createState() => _ClientDetailViewState();
}

class _ClientDetailViewState extends ConsumerState<ClientDetailView> {
  bool _isEditing = false;
  bool _isDeleting = false;
  late ClientRecord _client;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
  }

  Future<void> _confirmDelete() async {
    final clientName = _client.displayName.isNotEmpty
        ? _client.displayName
        : context.l10n.clients_thisClient;

    final shouldDelete = await showConfirmDialog(
      context,
      title: context.l10n.clients_deleteClient,
      message:
          '${context.l10n.clients_areYouSureYouWantToDelete} $clientName? ${context.l10n.clients_thisCannotBeUndone}',
      confirmLabel: context.l10n.common_delete,
    );

    if (!shouldDelete || !mounted) return;

    setState(() => _isDeleting = true);

    final notices = ref.read(noticeServiceProvider);
    try {
      await ref.read(clientsRepositoryProvider).deleteClient(_client.id);
      await _unlinkPhoneContact();
      ref.read(clientsRefreshProvider.notifier).bump();
      if (!mounted) return;
      setState(() => _isDeleting = false);
      notices.success(context.l10n.clients_clientDeletedSuccessfully);
      // A scrollController means we're inside a bottom sheet; close it.
      // Otherwise (split-layout detail pane) ask the host to clear the pane,
      // which still renders the just-deleted client until told to.
      if (widget.scrollController != null) {
        Navigator.pop(context);
      } else {
        widget.onDeleted?.call();
      }
    } catch (e, st) {
      ref.read(loggerProvider).warn('CLI-DEL deleteClient failed', e, st);
      if (!mounted) return;
      setState(() => _isDeleting = false);
      notices.error(
        composeErrorNotice(
          context,
          intro: context.l10n.error_introDeleteClient,
          tag: 'CLI-DEL',
          error: e,
        ),
      );
    }
  }

  /// Drops the device-local phone-contact link for the deleted client.
  /// Best-effort (mirrors CLI-CONTACT-SYNC): a failure must not fail the delete.
  Future<void> _unlinkPhoneContact() async {
    try {
      await ref.read(contactLinkStoreProvider).unlink(_client.id);
    } catch (e, st) {
      ref.read(loggerProvider).warn('CLI-DEL contact unlink failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DetailSheetListView(
      scrollController: widget.scrollController,
      showHandle: widget.showHandle,
      bottomPadding: widget.bottomPadding,
      children: [
        if (_isEditing)
          Text(
            context.l10n.clients_editClient,
            style: theme.textTheme.headlineLarge,
          )
        else
          _ViewHeader(client: _client),
        const SizedBox(height: AppSpacing.sp24),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp24),
        if (_isEditing)
          ClientEditForm(
            client: _client,
            isDeleting: _isDeleting,
            onDelete: _isDeleting ? null : _confirmDelete,
            onSaved: (updated) => setState(() {
              _client = updated;
              _isEditing = false;
            }),
          )
        else ...[
          ClientDetailViewBody(client: _client),
          const SizedBox(height: 24),
          _ViewActions(
            isDeleting: _isDeleting,
            onEdit: _isDeleting
                ? null
                : () => setState(() => _isEditing = true),
            onDelete: _isDeleting ? null : _confirmDelete,
          ),
        ],
      ],
    );
  }
}

class _ViewHeader extends StatelessWidget {
  const _ViewHeader({required this.client});

  final ClientRecord client;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fullName = [
      client.firstName,
      client.lastName,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();
    final showPersonName = fullName.isNotEmpty && fullName != client.name;
    return Column(
      children: [
        AppAvatar(name: client.displayName, size: AvatarSize.lg),
        const SizedBox(height: 12),
        Text(
          client.displayName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        if (showPersonName) ...[
          const SizedBox(height: 3),
          Text(
            fullName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _ViewActions extends StatelessWidget {
  const _ViewActions({
    required this.isDeleting,
    required this.onEdit,
    required this.onDelete,
  });

  final bool isDeleting;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;

    final editButton = FilledButton.icon(
      onPressed: onEdit,
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: Text(context.l10n.common_edit),
    );
    final deleteButton = OutlinedButton.icon(
      style: destructiveOutlinedButtonStyle(context),
      onPressed: onDelete,
      icon: BusyButtonIcon(
        isBusy: isDeleting,
        icon: Icons.delete_outline,
      ),
      label: Text(
        isDeleting ? context.l10n.clients_deleting : context.l10n.common_delete,
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          editButton,
          const SizedBox(height: AppSpacing.sp12),
          deleteButton,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: editButton),
        const SizedBox(width: 12),
        Expanded(child: deleteButton),
      ],
    );
  }
}
