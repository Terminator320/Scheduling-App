import 'package:flutter/foundation.dart';

@immutable
class WaveConnection {
  const WaveConnection({required this.businessId, required this.businessName});

  factory WaveConnection.fromMap(Map<String, dynamic> map) {
    return WaveConnection(
      businessId: (map['businessId'] as String?) ?? '',
      businessName: (map['businessName'] as String?) ?? '',
    );
  }

  final String businessId;
  final String businessName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveConnection &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          businessName == other.businessName;

  @override
  int get hashCode => Object.hash(businessId, businessName);
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
