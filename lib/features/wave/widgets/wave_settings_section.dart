import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/wave/application/wave_providers.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
import 'package:scheduling/features/wave/domain/wave_failure.dart';
import 'package:scheduling/features/wave/domain/wave_sync_notice.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Localized label for an automatic-import cadence — used by the picker row and
/// the action sheet.
String _scheduleLabel(BuildContext context, WaveImportSchedule schedule) =>
    switch (schedule) {
      WaveImportSchedule.off => context.l10n.wave_autoImportOff,
      WaveImportSchedule.weekly => context.l10n.wave_autoImportWeekly,
      WaveImportSchedule.monthly => context.l10n.wave_autoImportMonthly,
    };

/// Admin-only Wave integration controls in Settings. Holds ephemeral
/// [WaveConnection] and busy-flag state, and surfaces any [WaveFailure] via
/// notices — never ScaffoldMessenger.
class WaveSettingsSection extends ConsumerStatefulWidget {
  const WaveSettingsSection({super.key});

  @override
  ConsumerState<WaveSettingsSection> createState() =>
      _WaveSettingsSectionState();
}

class _WaveSettingsSectionState extends ConsumerState<WaveSettingsSection> {
  // This-session Connect result; takes precedence over the persisted
  // [waveConnectionProvider] status right after connecting.
  WaveConnection? _connection;
  bool _connectBusy = false;
  bool _syncBusy = false;
  bool _scheduleBusy = false;

  /// True while either Wave round trip is in flight. The cadence picker adds
  /// [_scheduleBusy] on top; the two buttons swap places, so neither needs it.
  bool get _busy => _connectBusy || _syncBusy;

  /// Fail-fast offline guard so the long-running Wave callables don't hang.
  /// Surfaces the network notice and returns true, so the caller can abort.
  bool _blockedOffline() {
    if (!ref.read(isOfflineProvider)) return false;
    ref
        .read(noticeServiceProvider)
        .error(const WaveNetwork().toLocalizedMessage(context));
    return true;
  }

  /// Shared try/on-WaveFailure/finally-busy-reset shape for the three actions
  /// below. Logs under `WAVE-<tag>` before showing the notice, so failures
  /// still reach Crashlytics.
  Future<void> _runWaveAction({
    required String tag,
    required void Function({required bool busy}) setBusy,
    required Future<void> Function() action,
  }) async {
    setBusy(busy: true);
    try {
      await action();
    } on WaveFailure catch (e, st) {
      if (!mounted) return;
      ref.read(loggerProvider).warn('WAVE-$tag failed', e, st);
      ref.read(noticeServiceProvider).error(e.toLocalizedMessage(context));
    } finally {
      if (mounted) setBusy(busy: false);
    }
  }

  Future<void> _connect() async {
    if (_blockedOffline()) return;
    await _runWaveAction(
      tag: 'CONNECT',
      setBusy: ({required busy}) => setState(() => _connectBusy = busy),
      action: () async {
        // No business chosen client-side — waveBootstrap resolves it
        // server-side, so the name never ships in the app.
        final conn = await ref.read(waveServiceProvider).bootstrap();
        if (!mounted) return;
        if (!conn.isConnected) {
          // Server returned no business (misconfigured WAVE_BUSINESS_NAME) —
          // don't show a blank "connected" state.
          ref
              .read(noticeServiceProvider)
              .error(context.l10n.wave_errorBusinessAmbiguous);
          return;
        }
        setState(() => _connection = conn);
        ref.invalidate(waveConnectionProvider);
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.wave_connectedSuccess(conn.businessName));
      },
    );
  }

  Future<void> _sync() async {
    if (_blockedOffline()) return;
    await _runWaveAction(
      tag: 'SYNC',
      setBusy: ({required busy}) => setState(() => _syncBusy = busy),
      action: () async {
        final summary = await ref.read(waveServiceProvider).syncCustomers();
        if (!mounted) return;
        ref
            .read(noticeServiceProvider)
            .success(waveSyncNotice(context.l10n, summary));
      },
    );
  }

  Future<void> _pickSchedule(WaveImportSchedule current) async {
    final choice = await showAdaptiveActionSheet<WaveImportSchedule>(
      context,
      title: context.l10n.wave_autoImportLabel,
      actions: [
        for (final s in WaveImportSchedule.values)
          AdaptiveSheetAction(value: s, label: _scheduleLabel(context, s)),
      ],
    );
    if (choice == null || choice == current) return;
    if (!mounted) return;
    if (_blockedOffline()) return;

    await _runWaveAction(
      tag: 'SCHEDULE',
      setBusy: ({required busy}) => setState(() => _scheduleBusy = busy),
      action: () async {
        await ref.read(waveServiceProvider).setImportSchedule(choice);
        if (!mounted) return;
        // Reflect the new cadence locally; invalidate so a later mount
        // re-reads the persisted value.
        final base = _connection ?? ref.read(waveConnectionProvider).value;
        if (base != null) {
          setState(() => _connection = base.copyWith(importSchedule: choice));
        }
        ref.invalidate(waveConnectionProvider);
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.wave_autoImportUpdated);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionAsync = ref.watch(waveConnectionProvider);
    // A this-session Connect wins; otherwise fall back to the cached persisted status.
    final connection = _connection ?? connectionAsync.value;
    final connected = connection != null;

    // Distinguish loading/error from not-connected, so a connected admin
    // doesn't see the Connect CTA flash, and a failure still offers a retry.
    if (_connection == null && connectionAsync.isLoading) {
      return const _WaveStatusLoading();
    }
    if (_connection == null && connectionAsync.hasError) {
      return _WaveStatusError(
        onRetry: () => ref.invalidate(waveConnectionProvider),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (connected)
          _ConnectedStatus(
            connection: connection,
            scheduleBusy: _scheduleBusy,
            onTapSchedule: _busy || _scheduleBusy
                ? null
                : () => _pickSchedule(connection.importSchedule),
          ),
        // Connect is first-time setup only — the status row replaces it once connected.
        if (!connected)
          AnimatedLoadingButton(
            label: context.l10n.wave_connectToWave,
            isLoading: _connectBusy,
            onPressed: _busy ? null : _connect,
          )
        else
          // Syncing only makes sense once connected — a tap while
          // disconnected is guaranteed to fail.
          AnimatedLoadingButton(
            label: context.l10n.wave_syncButton,
            isLoading: _syncBusy,
            onPressed: _busy ? null : _sync,
            variant: AnimatedLoadingButtonVariant.outlined,
          ),
      ],
    );
  }
}

/// The persisted-connection status row + auto-import schedule tile, shown
/// once Wave is connected.
class _ConnectedStatus extends StatelessWidget {
  const _ConnectedStatus({
    required this.connection,
    required this.scheduleBusy,
    required this.onTapSchedule,
  });

  final WaveConnection connection;
  final bool scheduleBusy;
  final VoidCallback? onTapSchedule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              const SizedBox(width: AppSpacing.sp8),
              Flexible(
                child: Text(
                  connection.businessName,
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
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sync_rounded),
          title: Text(context.l10n.wave_autoImportLabel),
          trailing: scheduleBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: AdaptiveProgressIndicator(),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _scheduleLabel(context, connection.importSchedule),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
          onTap: onTapSchedule,
        ),
      ],
    );
  }
}

/// Subtle placeholder while the persisted Wave status is still loading.
class _WaveStatusLoading extends StatelessWidget {
  const _WaveStatusLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sp12),
      child: Center(
        child: AdaptiveProgressIndicator(),
      ),
    );
  }
}

/// Inline error + retry shown when the Wave status read fails (rather than
/// silently rendering "not connected").
class _WaveStatusError extends StatelessWidget {
  const _WaveStatusError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
        const SizedBox(width: AppSpacing.sp8),
        Expanded(
          child: Text(
            context.l10n.error_somethingWentWrong,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(context.l10n.common_retry),
        ),
      ],
    );
  }
}
