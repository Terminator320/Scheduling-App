import 'package:cloud_firestore/cloud_firestore.dart';

class AppointmentImage {
  final String url;
  final String publicId;
  final String? thumbUrl;
  final String? fileName;
  final Timestamp? uploadedAt;

  AppointmentImage({
    required this.url,
    required this.publicId,
    this.thumbUrl,
    this.fileName,
    this.uploadedAt,
  });

  factory AppointmentImage.fromMap(Map<String, dynamic> data) {
    return AppointmentImage(
      url: (data['url'] ?? '').toString(),
      publicId: (data['publicId'] ?? '').toString(),
      thumbUrl: data['thumbUrl']?.toString(),
      fileName: data['fileName']?.toString(),
      uploadedAt: data['uploadedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'publicId': publicId,
      'thumbUrl': thumbUrl,
      'fileName': fileName,
      'uploadedAt': uploadedAt,
    };
  }
}