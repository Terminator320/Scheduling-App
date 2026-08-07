import 'package:flutter/foundation.dart';

import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';

@immutable
class WaveConnection {
  const WaveConnection({
    required this.businessId,
    required this.businessName,
    this.importSchedule = WaveImportSchedule.off,
  });

  factory WaveConnection.fromMap(Map<String, dynamic> map) {
    return WaveConnection(
      businessId: (map['businessId'] as String?) ?? '',
      businessName: (map['businessName'] as String?) ?? '',
      importSchedule: WaveImportSchedule.fromRaw(
        map['importSchedule'] as String?,
      ),
    );
  }

  final String businessId;
  final String businessName;
  final WaveImportSchedule importSchedule;

  /// True only when a real business is linked.
  bool get isConnected => businessId.isNotEmpty;

  WaveConnection copyWith({WaveImportSchedule? importSchedule}) =>
      WaveConnection(
        businessId: businessId,
        businessName: businessName,
        importSchedule: importSchedule ?? this.importSchedule,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveConnection &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          businessName == other.businessName &&
          importSchedule == other.importSchedule;

  @override
  int get hashCode => Object.hash(businessId, businessName, importSchedule);
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
