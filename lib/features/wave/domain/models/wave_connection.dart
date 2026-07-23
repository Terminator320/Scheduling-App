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

@immutable
class WaveImportSummary {
  const WaveImportSummary({
    required this.totalCount,
    required this.imported,
    required this.updated,
    required this.skippedArchived,
    required this.pages,
  });

  factory WaveImportSummary.fromMap(Map<String, dynamic> map) {
    return WaveImportSummary(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      imported: (map['imported'] as num?)?.toInt() ?? 0,
      updated: (map['updated'] as num?)?.toInt() ?? 0,
      skippedArchived: (map['skippedArchived'] as num?)?.toInt() ?? 0,
      pages: (map['pages'] as num?)?.toInt() ?? 0,
    );
  }

  final int totalCount;
  final int imported;
  final int updated;
  final int skippedArchived;
  final int pages;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveImportSummary &&
          runtimeType == other.runtimeType &&
          totalCount == other.totalCount &&
          imported == other.imported &&
          updated == other.updated &&
          skippedArchived == other.skippedArchived &&
          pages == other.pages;

  @override
  int get hashCode =>
      Object.hash(totalCount, imported, updated, skippedArchived, pages);
}
