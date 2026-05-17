import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  static const double maxImageDimension = 1600;
  static const int imageQuality = 80;

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

    if (images.isEmpty) return [];

    return images.map((x) => File(x.path)).toList();
  }
}
