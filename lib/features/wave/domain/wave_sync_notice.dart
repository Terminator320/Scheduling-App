import 'package:scheduling/features/wave/domain/models/wave_connection.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Composes the success notice for a "Sync with Wave" run.
///
/// Every part names its own destination, because the sync moves clients in
/// BOTH directions and a bare "5 added" leaves the admin guessing which side
/// grew. Zero-valued parts are dropped rather than printed, so a one-sided run
/// reads as one clause instead of a row of zeros.
///
/// The last three parts exist so silence can't be mistaken for success, which
/// is the failure mode this composer is most exposed to — a bounded push, a
/// dead-lettered job and a push that threw all leave the counters at zero:
///  * `pushedPending` — the push is bounded, so without it a 3-of-200 drain
///    reports "3 clients added to Wave" and reads as a finished sync.
///  * `pushedFailed` — dead-lettered jobs are not queued and never retry, so
///    they would otherwise be reported as "already up to date" when in fact
///    those clients can now only reach Wave by hand.
///  * `pushIncomplete` — a broken push and an empty queue produce identical
///    zeros, and only one of them is good news.
String waveSyncNotice(AppLocalizations l10n, WaveSyncSummary summary) {
  final parts = <String>[
    if (summary.pushedCreated > 0)
      l10n.wave_syncAddedToWave(summary.pushedCreated),
    if (summary.pushedUpdated > 0)
      l10n.wave_syncUpdatedInWave(summary.pushedUpdated),
    if (summary.imported > 0) l10n.wave_syncAddedToApp(summary.imported),
    if (summary.updated > 0) l10n.wave_syncUpdatedInApp(summary.updated),
    if (summary.pushedFailed > 0)
      l10n.wave_syncFailedToWave(summary.pushedFailed),
    if (summary.pushedPending > 0)
      l10n.wave_syncStillQueued(summary.pushedPending),
    if (summary.pushIncomplete) l10n.wave_syncPushIncomplete,
  ];
  if (parts.isEmpty) return l10n.wave_syncUpToDate;
  return l10n.wave_syncResult(parts.join(', '));
}
