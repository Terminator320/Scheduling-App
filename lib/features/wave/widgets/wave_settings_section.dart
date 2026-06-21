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
  WaveConnection? _connection;
  bool _connectBusy = false;
  bool _importBusy = false;

  Future<void> _connect() async {
    setState(() => _connectBusy = true);
    try {
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
            context.l10n.wave_importSuccess(summary.imported, summary.updated),
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
        AnimatedLoadingButton(
          label: context.l10n.wave_connectToWave,
          isLoading: _connectBusy,
          onPressed: _connectBusy || _importBusy ? null : _connect,
          variant: connected
              ? AnimatedLoadingButtonVariant.outlined
              : AnimatedLoadingButtonVariant.filled,
        ),
        const SizedBox(height: AppSpacing.sp8),
        AnimatedLoadingButton(
          label: context.l10n.wave_importCustomers,
          isLoading: _importBusy,
          // Gate on having an active connection for clarity; the server enforces
          // the precondition as well (WaveValidation if not bootstrapped).
          onPressed: connected && !_connectBusy && !_importBusy
              ? _import
              : null,
          variant: AnimatedLoadingButtonVariant.outlined,
        ),
      ],
    );
  }
}
