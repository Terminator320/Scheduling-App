import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:scheduling/core/logging/app_logger.dart';

class ImagePickerService {
  ImagePickerService({ImagePicker? picker, AppLogger? logger})
    : _picker = picker ?? ImagePicker(),
      _logger = logger ?? AppLogger();

  static const double maxImageDimension = 1600;
  // image_picker handles native resize and JPEG compression.
  static const int imageQuality = 70;

  final ImagePicker _picker;
  final AppLogger _logger;

  Future<File?> pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: maxImageDimension,
        maxHeight: maxImageDimension,
        imageQuality: imageQuality,
      );
      if (pickedFile == null) return null;

      return File(pickedFile.path);
    } catch (e, st) {
      _logger.warn('IMG-PICK single pick failed', e, st);
      return null;
    }
  }

  Future<List<File>> pickMultiImages() async {
    try {
      final images = await _picker.pickMultiImage(
        maxWidth: maxImageDimension,
        maxHeight: maxImageDimension,
        imageQuality: imageQuality,
      );

      return [for (final image in images) File(image.path)];
    } catch (e, st) {
      _logger.warn('IMG-PICK multi pick failed', e, st);
      return const [];
    }
  }
}
