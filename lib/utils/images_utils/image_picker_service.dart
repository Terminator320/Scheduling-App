import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  // single image
  Future<File?> pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return null;

    return File(pickedFile.path);
  }

  // multiple images
  Future<List<File>> pickMultiImages() async {
    final List<XFile>? images = await _picker.pickMultiImage();

    if (images == null || images.isEmpty) return [];

    return images.map((x) => File(x.path)).toList();
  }
}