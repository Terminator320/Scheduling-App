import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/edit_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/views/client_view_body.dart';
import 'package:scheduling/l10n/l10n.dart';
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
  });

  final ClientRecord client;
  final ScrollController? scrollController;
  final bool showHandle;
  final double bottomPadding;

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
    // Null means cancelled. Clients are never removed, so this view always has
    // a record to keep showing.
    if (!mounted || updated == null) return;
    setState(() => _client = updated);
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
        _ViewHeader(client: _client),
        const SizedBox(height: AppSpacing.sp16),
        _EditPill(onEdit: _openEdit),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp24),
        ClientDetailViewBody(client: _client, onBookJob: _bookJob),
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
        const SizedBox(height: AppSpacing.sp12),
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

/// Right-aligned Edit pill. It sits with the profile header rather than
/// floating above it, and it is the only affordance here — clients are never
/// archived or deleted (owner decision 2026-08-01).
class _EditPill extends StatelessWidget {
  const _EditPill({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: theme.palette.primaryAccent.withValues(alpha: 0.10),
          foregroundColor: theme.palette.primaryAccent,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: AppSpacing.sp8,
          ),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
        ),
        onPressed: onEdit,
        child: Text(context.l10n.clients_editClientPill),
      ),
    );
  }
}
