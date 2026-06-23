import 'package:flutter/foundation.dart';

/// A Wave business the connected token can access. Returned by the
/// `waveListBusinesses` callable to drive the connect-flow business picker.
@immutable
class WaveBusiness {
  const WaveBusiness({required this.id, required this.name});

  factory WaveBusiness.fromMap(Map<String, dynamic> map) {
    return WaveBusiness(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
    );
  }

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveBusiness &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => Object.hash(id, name);
}
