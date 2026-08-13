import 'package:flutter/foundation.dart';

import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';

@immutable
class WaveConnection {
  const WaveConnection({
    required this.businessId,
    required this.businessName,
    this.importSchedule = WaveImportSchedule.off,
    this.pendingCount,
    this.failedCount,
  });

  factory WaveConnection.fromMap(Map<String, dynamic> map) {
    return WaveConnection(
      businessId: (map['businessId'] as String?) ?? '',
      businessName: (map['businessName'] as String?) ?? '',
      importSchedule: WaveImportSchedule.fromRaw(
        map['importSchedule'] as String?,
      ),
      pendingCount: (map['pendingCount'] as num?)?.toInt(),
      failedCount: (map['failedCount'] as num?)?.toInt(),
    );
  }

  final String businessId;
  final String businessName;
  final WaveImportSchedule importSchedule;

  /// Client edits queued for Wave but not pushed yet.
  ///
  /// **Nullable, and null is NOT zero.** Zero means the outbox is empty, which
  /// is the one reading an admin would act on by not pressing Sync — so a
  /// count the server could not take (or an older backend that does not send
  /// the field) has to be distinguishable from it. Every surface renders null
  /// as "nothing shown", never as "nothing pending".
  final int? pendingCount;

  /// Client edits that gave up — dead-lettered, so nothing retries them on
  /// its own. Recoverable only through "Retry failed".
  ///
  /// Same null-is-unknown contract as [pendingCount].
  final int? failedCount;

  /// True only when a real business is linked.
  bool get isConnected => businessId.isNotEmpty;

  /// Whether there is outbox work worth telling the admin about.
  bool get hasPending => (pendingCount ?? 0) > 0;

  /// Whether any client edit has permanently failed to reach Wave.
  bool get hasFailed => (failedCount ?? 0) > 0;

  WaveConnection copyWith({
    WaveImportSchedule? importSchedule,
    int? pendingCount,
    int? failedCount,
  }) => WaveConnection(
    businessId: businessId,
    businessName: businessName,
    importSchedule: importSchedule ?? this.importSchedule,
    pendingCount: pendingCount ?? this.pendingCount,
    failedCount: failedCount ?? this.failedCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveConnection &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          businessName == other.businessName &&
          importSchedule == other.importSchedule &&
          pendingCount == other.pendingCount &&
          failedCount == other.failedCount;

  @override
  int get hashCode => Object.hash(
    businessId,
    businessName,
    importSchedule,
    pendingCount,
    failedCount,
  );
}

/// What one "Retry failed" press recovered.
@immutable
class WaveRetryResult {
  const WaveRetryResult({
    required this.requeued,
    required this.scanned,
    required this.pushed,
  });

  factory WaveRetryResult.fromMap(Map<String, dynamic> map) => WaveRetryResult(
    requeued: (map['requeued'] as num?)?.toInt() ?? 0,
    scanned: (map['scanned'] as num?)?.toInt() ?? 0,
    pushed: (map['pushed'] as num?)?.toInt(),
  );

  /// Jobs returned to the queue. This is the durable part of the action.
  final int requeued;

  /// Dead jobs examined. Larger than [requeued] when one was re-enqueued by a
  /// concurrent client edit and therefore left alone.
  final int scanned;

  /// How many actually reached Wave on the push that followed, or null when
  /// that push failed or was skipped. Null is NOT zero: the requeue still
  /// committed, so the jobs are queued and will drain.
  final int? pushed;
}

/// What one "Sync with Wave" run moved, in both directions.
///
/// `imported`/`updated` are what landed in THIS APP; `pushedCreated`/
/// `pushedUpdated` are what landed in WAVE. `pushedPending` is the outbox
/// backlog the interactive sync didn't get through — the scheduled worker
/// finishes those, and the notice says so rather than implying the sync
/// covered everything.
@immutable
class WaveSyncSummary {
  const WaveSyncSummary({
    required this.totalCount,
    required this.imported,
    required this.updated,
    required this.skippedArchived,
    required this.pages,
    required this.pushedCreated,
    required this.pushedUpdated,
    required this.pushedPending,
    required this.pushedFailed,
    required this.pushIncomplete,
  });

  factory WaveSyncSummary.fromMap(Map<String, dynamic> map) {
    return WaveSyncSummary(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      imported: (map['imported'] as num?)?.toInt() ?? 0,
      updated: (map['updated'] as num?)?.toInt() ?? 0,
      skippedArchived: (map['skippedArchived'] as num?)?.toInt() ?? 0,
      pages: (map['pages'] as num?)?.toInt() ?? 0,
      pushedCreated: (map['pushedCreated'] as num?)?.toInt() ?? 0,
      pushedUpdated: (map['pushedUpdated'] as num?)?.toInt() ?? 0,
      pushedPending: (map['pushedPending'] as num?)?.toInt() ?? 0,
      pushedFailed: (map['pushedFailed'] as num?)?.toInt() ?? 0,
      pushIncomplete: map['pushIncomplete'] == true,
    );
  }

  final int totalCount;
  final int imported;
  final int updated;
  final int skippedArchived;
  final int pages;
  final int pushedCreated;
  final int pushedUpdated;
  final int pushedPending;

  /// Clients the push gave up on — dead-lettered, so they will NOT retry.
  final int pushedFailed;

  /// True when the push half itself errored. Distinguishes "the queue was
  /// empty" from "we could not find out", which produce identical zeros.
  final bool pushIncomplete;
}
