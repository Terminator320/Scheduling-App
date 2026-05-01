import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  static const maxImageDimension = 1600.0;
  static const imageQuality = 85;

  final ImagePicker _picker = ImagePicker();

  // single image
  Future<File?> pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return null;

    return File(pickedFile.path);
  }

  // multiple images
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
