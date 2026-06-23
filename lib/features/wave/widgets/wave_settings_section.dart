import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/wave/application/wave_providers.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';
import 'package:scheduling/features/wave/domain/wave_failure.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Admin-only Wave integration controls shown inside the Settings screen.
///
/// Holds ephemeral state for the active [WaveConnection] and per-action busy
/// flags. Both actions surface [WaveFailure] via notices; they never use
/// ScaffoldMessenger.
class WaveSettingsSection extends ConsumerStatefulWidget {
  const WaveSettingsSection({super.key});

  @override
  ConsumerState<WaveSettingsSection> createState() =>
      _WaveSettingsSectionState();
}

class _WaveSettingsSectionState extends ConsumerState<WaveSettingsSection> {
  // Hydrated on mount from the persisted server-side connection via the
  // admin-only waveGetConnection callable — the app can't read the
  // firestore.rules-locked `wave` collection directly. Reflects real
  // connection status across launches, not just a Connect done this session.
  WaveConnection? _connection;
  bool _connectBusy = false;
  bool _importBusy = false;

  @override
  void initState() {
    super.initState();
    _loadConnection();
  }

  Future<void> _loadConnection() async {
    try {
      final conn = await ref.read(waveServiceProvider).getConnection();
      if (!mounted) return;
      setState(() => _connection = conn);
    } on WaveFailure {
      // Status read failed (offline / transient) — leave as not-connected. The
      // service already logged; don't push a notice on every settings open.
    }
  }

  Future<void> _connect() async {
    setState(() => _connectBusy = true);
    try {
      // No business is chosen client-side — waveBootstrap resolves the target
      // from its server-side WAVE_BUSINESS_NAME config, so the business name
      // never ships in the app.
      final conn = await ref.read(waveServiceProvider).bootstrap();
      if (!mounted) return;
      setState(() => _connection = conn);
      ref
          .read(noticeServiceProvider)
          .success(context.l10n.wave_connectedSuccess(conn.businessName));
    } on WaveFailure catch (e) {
      if (!mounted) return;
      ref.read(noticeServiceProvider).error(e.toLocalizedMessage(context));
    } finally {
      if (mounted) setState(() => _connectBusy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _importBusy = true);
    try {
      final summary = await ref.read(waveServiceProvider).importCustomers();
      if (!mounted) return;
      ref
          .read(noticeServiceProvider)
          .success(
            context.l10n.wave_importSuccess(
              summary.imported,
              summary.updated,
              summary.skippedArchived,
            ),
          );
    } on WaveFailure catch (e) {
      if (!mounted) return;
      ref.read(noticeServiceProvider).error(e.toLocalizedMessage(context));
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = _connection != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (connected) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.sp4,
              bottom: AppSpacing.sp8,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 14,
                  color: Theme.of(context).statusColors.success,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _connection!.businessName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        // Connect is first-time setup only — once connected, the persisted
        // status row replaces it and only Import remains.
        if (!connected) ...[
          AnimatedLoadingButton(
            label: context.l10n.wave_connectToWave,
            isLoading: _connectBusy,
            onPressed: _connectBusy || _importBusy ? null : _connect,
            variant: AnimatedLoadingButtonVariant.filled,
          ),
          const SizedBox(height: AppSpacing.sp8),
        ],
        AnimatedLoadingButton(
          label: context.l10n.wave_importCustomers,
          isLoading: _importBusy,
          onPressed: !_connectBusy && !_importBusy ? _import : null,
          variant: AnimatedLoadingButtonVariant.outlined,
        ),
      ],
    );
  }
}
