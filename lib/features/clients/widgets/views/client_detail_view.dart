import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/testing_flags.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/clients/application/client_form_controller.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/widgets/sheets/edit_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/views/client_view_body.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// Read-only client detail. Editing happens in a sheet above this view, so the
/// view never swaps into a form.
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

  /// How the host dismisses this view once its record is gone — the sheet pops
  /// itself, the two-pane detail clears its selection. The host decides, since
  /// only it knows how it is presented.
  // TODO(george): remove with kShowTestingDeleteClient (#pre-ship)
  final VoidCallback? onDeleted;

  @override
  ConsumerState<ClientDetailView> createState() => _ClientDetailViewState();
}

class _ClientDetailViewState extends ConsumerState<ClientDetailView> {
  late ClientRecord _client;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
  }

  Future<void> _openEdit() async {
    final updated = await showEditClientSheet(context, _client);
    // Null means cancelled. Editing never removes the record, so this view
    // always has one to keep showing.
    if (!mounted || updated == null) return;
    setState(() => _client = updated);
  }

  // TODO(george): remove with kShowTestingDeleteClient (#pre-ship)
  Future<void> _confirmTestingDelete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete client? (testing only)',
      message:
          'Permanently deletes ${_client.displayName}. Past appointments keep '
          'the name but stop linking to them. This action is debug-only and '
          'must not ship.',
      // The dialog's Cancel comes from l10n, so this reuses the existing key
      // rather than sitting in English beside a translated button.
      confirmLabel: context.l10n.common_delete,
    );
    if (!ok || !mounted) return;

    final notices = ref.read(noticeServiceProvider);
    final outcome = await ref
        .read(clientFormControllerProvider.notifier)
        .deleteClient(_client.id);
    if (!mounted) return;
    switch (outcome) {
      case ClientDeleted():
        notices.success('Client deleted.');
        widget.onDeleted?.call();
      case ClientDeleteFailed(:final error):
        notices.error(
          composeErrorNotice(
            context,
            // Debug-only affordance, so this string stays inline with the other
            // five rather than adding an ARB key that has to be swept later.
            intro: "Couldn't delete the client",
            tag: 'CLI-DEL',
            error: error,
          ),
        );
    }
  }

  Future<void> _bookJob() async {
    await showAddEventPopup(context, initialClient: _client);
  }

  @override
  Widget build(BuildContext context) {
    return DetailSheetListView(
      scrollController: widget.scrollController,
      showHandle: widget.showHandle,
      bottomPadding: widget.bottomPadding,
      children: [
        _ProfileCard(client: _client, onEdit: _openEdit),
        const SizedBox(height: AppSpacing.sp16),
        ClientDetailViewBody(client: _client, onBookJob: _bookJob),
        // TODO(george): remove with kShowTestingDeleteClient (#pre-ship)
        if (kShowTestingDeleteClient) ...[
          const SizedBox(height: AppSpacing.sp24),
          OutlinedButton.icon(
            style: destructiveOutlinedButtonStyle(
              context,
              minimumSize: const Size(double.infinity, 48),
            ),
            onPressed: ref.watch(clientFormControllerProvider)
                ? null
                : _confirmTestingDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete client (testing)'),
          ),
        ],
      ],
    );
  }
}

/// Avatar, name, a `<type> · since <Mon YYYY>` line, and the Edit pill — one
/// card, as the approved design draws it. The pill lives inside the card rather
/// than floating above it.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.client, required this.onEdit});

  final ClientRecord client;
  final VoidCallback onEdit;

  /// "Property mgmt · since Apr 2023" — either half is dropped when absent,
  /// so a typeless client with no createdAt renders no line at all.
  String _subtitle(BuildContext context) {
    final l10n = context.l10n;
    final parts = <String>[
      if (client.type != ClientType.unset) clientTypeLabel(l10n, client.type),
      if (client.createdAt != null)
        l10n.clients_sinceDate(
          // Locale-aware month+year: "Apr 2023" / "avr. 2023".
          DateFormat.yMMM(
            Localizations.localeOf(context).toString(),
          ).format(client.createdAt!),
        ),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _subtitle(context);
    // Shown only when it says something the name doesn't already — a business
    // with a named individual on file.
    final fullName = [
      client.firstName,
      client.lastName,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();
    final showPersonName = fullName.isNotEmpty && fullName != client.name;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          client.displayName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.palette.textTertiary,
            ),
          ),
        ],
        if (showPersonName) ...[
          const SizedBox(height: 3),
          Text(
            fullName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.palette.textTertiary,
            ),
          ),
        ],
      ],
    );

    final pill = _EditPill(onEdit: onEdit);

    return DecoratedBox(
      decoration: appCardDecoration(
        theme,
        radius: AppRadius.r16,
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        // The row holds an avatar, two-to-three text lines and a pill, so it
        // folds rather than overflow once text is scaled up.
        child: context.isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppAvatar(name: client.displayName, size: AvatarSize.lg),
                      const SizedBox(width: AppSpacing.sp12),
                      Expanded(child: identity),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sp12),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: pill,
                  ),
                ],
              )
            : Row(
                children: [
                  AppAvatar(name: client.displayName, size: AvatarSize.lg),
                  const SizedBox(width: AppSpacing.sp12),
                  Expanded(child: identity),
                  const SizedBox(width: AppSpacing.sp8),
                  pill,
                ],
              ),
      ),
    );
  }
}

/// Tinted Edit pill. The only shipping affordance on this surface — clients are
/// never archived or deleted (owner decision 2026-08-01).
class _EditPill extends StatelessWidget {
  const _EditPill({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: accentPillButtonStyle(context),
      onPressed: onEdit,
      child: Text(context.l10n.common_edit),
    );
  }
}
