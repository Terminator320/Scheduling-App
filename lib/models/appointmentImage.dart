import 'package:cloud_firestore/cloud_firestore.dart';

class AppointmentImage {
  final String url;
  final String storagePath;
  final String? fileName;
  final Timestamp? uploadedAt;

  AppointmentImage({
    required this.url,
    required this.storagePath,
    this.fileName,
    this.uploadedAt,
  });

  factory AppointmentImage.fromMap(Map<String, dynamic> data) {
    return AppointmentImage(
      url: (data['url'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      fileName: data['fileName']?.toString(),
      uploadedAt: data['uploadedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'storagePath': storagePath,
      'fileName': fileName,
      'uploadedAt': uploadedAt,
    };
  }
}
