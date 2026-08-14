import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scheduling/core/utils/firestore_parsing.dart';

part 'appointment_image.freezed.dart';

@freezed
abstract class AppointmentImage with _$AppointmentImage {
  const factory AppointmentImage({
    @Default('') String url,
    @Default('') String storagePath,
    // Round-tripped but never read off an instance: the rendered name comes
    // from storagePath. Kept so an existing doc's field survives a rewrite.
    String? fileName,
    DateTime? uploadedAt,
  }) = _AppointmentImage;
  const AppointmentImage._();

  factory AppointmentImage.fromMap(Map<String, dynamic> data) {
    return AppointmentImage(
      url: (data['url'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      fileName: data['fileName']?.toString(),
      uploadedAt: firestoreDateTime(data['uploadedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'url': url,
    'storagePath': storagePath,
    'fileName': fileName,
    'uploadedAt': uploadedAt,
  };
}
