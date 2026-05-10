import 'package:freezed_annotation/freezed_annotation.dart';

part 'appointment_image.freezed.dart';

/// One image attached to an appointment. Stored under the `pictures` array
/// of the parent appointment doc; binary lives in Firebase Storage at
/// `storagePath`.
@freezed
abstract class AppointmentImage with _$AppointmentImage {
  const AppointmentImage._();

  const factory AppointmentImage({
    @Default('') String url,
    @Default('') String storagePath,
    String? fileName,
    DateTime? uploadedAt,
  }) = _AppointmentImage;

  factory AppointmentImage.fromMap(Map<String, dynamic> data) {
    return AppointmentImage(
      url: (data['url'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      fileName: data['fileName']?.toString(),
      uploadedAt: _parseDateTime(data['uploadedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'url': url,
    'storagePath': storagePath,
    'fileName': fileName,
    'uploadedAt': uploadedAt,
  };

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    // Avoid importing cloud_firestore in the domain layer; check by name.
    final type = value.runtimeType.toString();
    if (type == 'Timestamp') {
      // ignore: avoid_dynamic_calls
      return (value as dynamic).toDate() as DateTime;
    }
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
