import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  static const double maxImageDimension = 1600;
  // image_picker resizes and JPEG-compresses natively at decode time, so no separate compression pass is needed.
  static const int imageQuality = 70;

  final ImagePicker _picker = ImagePicker();

  Future<File?> pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: maxImageDimension,
      maxHeight: maxImageDimension,
      imageQuality: imageQuality,
    );
    if (pickedFile == null) return null;

    return File(pickedFile.path);
  }

  Future<List<File>> pickMultiImages() async {
    final images = await _picker.pickMultiImage(
      maxWidth: maxImageDimension,
      maxHeight: maxImageDimension,
      imageQuality: imageQuality,
    );

    return images.map((x) => File(x.path)).toList();
  }
}
