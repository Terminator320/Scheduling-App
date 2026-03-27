import 'package:cloud_firestore/cloud_firestore.dart';

class AppointmentRecord {
  final String id;
  final String title;
  final String date;
  final String startTime;
  final String endTime;
  final String clientId;
  final String clientName;
  final String clientPhone;
  final String employeeId;
  final String employeeName;
  final String address;
  final String notes;
  final String materialsNeeded;
  final String pictures;
  final String status;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  AppointmentRecord({
    required this.id,
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    required this.employeeId,
    required this.employeeName,
    required this.address,
    required this.notes,
    required this.materialsNeeded,
    required this.pictures,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppointmentRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return AppointmentRecord(
      id: doc.id,
      title: data['title'] ?? '',
      date: data['date'] ?? '',
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'] ?? '',
      clientPhone: data['clientPhone'] ?? '',
      employeeId: data['employeeId'] ?? '',
      employeeName: data['employeeName'] ?? '',
      address: data['address'] ?? '',
      notes: data['notes'] ?? '',
      materialsNeeded: data['materialsNeeded'] ?? '',
      pictures: data['pictures'] ?? '',
      status: data['status'] ?? 'booked',
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'clientId': clientId,
      'clientName': clientName,
      'clientPhone': clientPhone,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'address': address,
      'notes': notes,
      'materialsNeeded': materialsNeeded,
      'pictures': pictures,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}