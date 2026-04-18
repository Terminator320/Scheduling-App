import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class ImageStorageService {

  Future<String> uploadImage(File file) async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child(
        "events/${DateTime.now().millisecondsSinceEpoch}.jpg",
      );

      await storageRef.putFile(file);

      return await storageRef.getDownloadURL();
    } catch (e) {
      // print("Upload Error: $e");
      rethrow;
    }
  }

  Future<List<String>> uploadImages(List<File> files) async {
    // uploads all at once
    final urls = await Future.wait(files.map((f) => uploadImage(f)));

    return urls;
  }
}
