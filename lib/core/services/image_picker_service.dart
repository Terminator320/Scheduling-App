import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  // Downsize images before they reach compression/upload to reduce memory and storage use.
  static const double maxImageDimension = 1600;
  static const int imageQuality = 80;

  final ImagePicker _picker = ImagePicker();

  // single image
  Future<File?> pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: maxImageDimension,
      maxHeight: maxImageDimension,
      imageQuality: imageQuality,
    );
    if (pickedFile == null) return null;

    return File(pickedFile.path);
  }

  // multiple images
  Future<List<File>> pickMultiImages() async {
    final List<XFile> images = await _picker.pickMultiImage(
      maxWidth: maxImageDimension,
      maxHeight: maxImageDimension,
      imageQuality: imageQuality,
    );

    if (images.isEmpty) return [];

    return images.map((x) => File(x.path)).toList();
  }
}
