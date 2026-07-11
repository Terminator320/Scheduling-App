import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/wave/application/wave_providers.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
import 'package:scheduling/features/wave/domain/wave_failure.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Localized label for an automatic-import cadence — used by the picker row and
/// the action sheet.
String _scheduleLabel(BuildContext context, WaveImportSchedule schedule) =>
    switch (schedule) {
      WaveImportSchedule.off => context.l10n.wave_autoImportOff,
      WaveImportSchedule.weekly => context.l10n.wave_autoImportWeekly,
      WaveImportSchedule.monthly => context.l10n.wave_autoImportMonthly,
    };

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
  // Connection done in the current session. The persisted server-side status is
  // read separately via [waveConnectionProvider] (a cached callable, since the
  // app can't read the firestore.rules-locked `wave` collection directly); this
  // local value takes precedence right after a Connect.
  WaveConnection? _connection;
  bool _connectBusy = false;
  bool _importBusy = false;
  bool _scheduleBusy = false;

  Future<void> _connect() async {
    setState(() => _connectBusy = true);
    try {
      // No business is chosen client-side — waveBootstrap resolves the target
      // from its server-side WAVE_BUSINESS_NAME config, so the business name
      // never ships in the app.
      final conn = await ref.read(waveServiceProvider).bootstrap();
      if (!mounted) return;
      if (!conn.isConnected) {
        // Server returned no business (e.g. misconfigured WAVE_BUSINESS_NAME) —
        // don't flip the UI to a blank "connected" state.
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

    setState(() => _scheduleBusy = true);
    try {
      await ref.read(waveServiceProvider).setImportSchedule(choice);
      if (!mounted) return;
      // Reflect the new cadence locally; the connection provider is invalidated
      // so a later Settings mount re-reads the persisted value.
      final base = _connection ?? ref.read(waveConnectionProvider).value;
      if (base != null) {
        setState(() => _connection = base.copyWith(importSchedule: choice));
      }
      ref.invalidate(waveConnectionProvider);
      ref
          .read(noticeServiceProvider)
          .success(context.l10n.wave_autoImportUpdated);
    } on WaveFailure catch (e) {
      if (!mounted) return;
      ref.read(noticeServiceProvider).error(e.toLocalizedMessage(context));
    } finally {
      if (mounted) setState(() => _scheduleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connectionAsync = ref.watch(waveConnectionProvider);
    // A Connect done this session wins; otherwise fall back to the cached
    // persisted status.
    final connection = _connection ?? connectionAsync.value;
    final connected = connection != null;

    // Distinguish "still loading" and "read failed" from "not connected" so an
    // already-connected admin doesn't see the Connect CTA flash, and a genuine
    // failure offers a retry instead of masquerading as never-connected.
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
            trailing: _scheduleBusy
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
            onTap: _connectBusy || _importBusy || _scheduleBusy
                ? null
                : () => _pickSchedule(connection.importSchedule),
          ),
        ],
        // Connect is first-time setup only — once connected, the persisted
        // status row replaces it and only Import remains.
        if (!connected)
          AnimatedLoadingButton(
            label: context.l10n.wave_connectToWave,
            isLoading: _connectBusy,
            onPressed: _connectBusy || _importBusy ? null : _connect,
          )
        else
          // Import only makes sense once connected — a tap while disconnected
          // is guaranteed to fail.
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
