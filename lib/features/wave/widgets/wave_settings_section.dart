import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/wave/application/wave_providers.dart';
import 'package:scheduling/features/wave/domain/models/wave_business.dart';
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
  // NOTE: session-only. The app intentionally never reads Wave connection state
  // (firestore.rules locks the `wave` collection to clients), so this resets to
  // null on every fresh mount. The connected row/affordance therefore reflects
  // only a Connect performed in the current session, not server-side state.
  WaveConnection? _connection;
  bool _connectBusy = false;
  bool _importBusy = false;

  Future<void> _connect() async {
    setState(() => _connectBusy = true);
    try {
      final service = ref.read(waveServiceProvider);
      final businesses = await service.listBusinesses();
      if (!mounted) return;

      if (businesses.isEmpty) {
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.wave_noBusinessesFound);
        return;
      }

      final WaveBusiness target;
      if (businesses.length == 1) {
        target = businesses.first;
      } else {
        final picked = await showDialog<WaveBusiness>(
          context: context,
          builder: (_) => _WaveBusinessPickerDialog(businesses: businesses),
        );
        if (picked == null) return; // dismissed — connect quietly aborts
        target = picked;
      }

      final conn = await service.bootstrap(businessId: target.id);
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
          onPressed: !_connectBusy && !_importBusy ? _import : null,
          variant: AnimatedLoadingButtonVariant.outlined,
        ),
      ],
    );
  }
}

/// Lets the admin pick which Wave business to connect when the token's account
/// exposes several. Pops the chosen [WaveBusiness], or null when dismissed.
class _WaveBusinessPickerDialog extends StatelessWidget {
  const _WaveBusinessPickerDialog({required this.businesses});

  final List<WaveBusiness> businesses;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(context.l10n.wave_pickBusinessTitle),
      children: [
        for (final business in businesses)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(business),
            child: Text(business.name.isEmpty ? business.id : business.name),
          ),
      ],
    );
  }
}
