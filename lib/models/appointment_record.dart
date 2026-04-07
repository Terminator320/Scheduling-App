import 'package:cloud_firestore/cloud_firestore.dart';

class AppointmentRecord {
  final String? id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String clientId;
  final String clientName;
  final String clientPhone;
  final List<String> employeeIds;
  final List<String> employeeNames;
  final String address;
  final String notes;
  final String materialsNeeded;
  final String status;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final List<String> pictures;

  AppointmentRecord({
    this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    required this.employeeIds,
    required this.employeeNames,
    required this.address,
    required this.notes,
    required this.materialsNeeded,
    required this.status,
    this.createdAt,
    this.updatedAt,
    required this.pictures
  });

  factory AppointmentRecord.fromMap(String id, Map<String, dynamic> data) {
    return AppointmentRecord(
      id: id,
      title: (data['title'] ?? '').toString(),
      startTime: _parseDateTime(data['startTime']),
      endTime: _parseDateTime(data['endTime']),
      clientId: (data['clientId'] ?? '').toString(),
      clientName: (data['clientName'] ?? '').toString(),
      clientPhone: (data['clientPhone'] ?? '').toString(),
      employeeIds: _pasrseStringList(data['employeeIds']),
      employeeNames: _pasrseStringList(data['employeeNames']),
      address: (data['address'] ?? '').toString(),
      notes: (data['notes'] ?? '').toString(),
      materialsNeeded: (data['materialsNeeded'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      pictures: _pasrseStringList(data['pictures']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'clientId': clientId,
      'clientName': clientName,
      'clientPhone': clientPhone,
      'employeeIds': employeeIds,
      'employeeNames': employeeNames,
      'address': address,
      'notes': notes,
      'pictures': pictures,
      'materialsNeeded': materialsNeeded,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  static List<String> _pasrseStringList(dynamic value) {
    if (value is List) return List<String>.from(value);
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }
}
