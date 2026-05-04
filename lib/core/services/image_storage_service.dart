import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:scheduling/features/calendar/models/appointment_image.dart';

class ImageStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<AppointmentImage> uploadImage(String appointmentId, File file) async {
    final originalName = file.uri.pathSegments.last;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$originalName';
    final path = 'appointments/$appointmentId/images/$fileName';

    final ref = _storage.ref(path);
    final metadata = SettableMetadata(
      contentType: _contentTypeFor(originalName),
      cacheControl: 'public, max-age=31536000',
    );

    final snapshot = await ref.putFile(file, metadata);
    final url = await snapshot.ref.getDownloadURL();

    return AppointmentImage(
      url: url,
      storagePath: path,
      fileName: fileName,
      uploadedAt: Timestamp.now(),
    );
  }

  Future<List<AppointmentImage>> uploadImages(
    String appointmentId,
    List<File> files,
  ) async {
    return Future.wait(files.map((f) => uploadImage(appointmentId, f)));
  }

  Future<void> deleteImage(AppointmentImage image) async {
    if (image.storagePath.isEmpty) return;
    try {
      await _storage.ref(image.storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      rethrow;
    }
  }

  Future<void> deleteImages(List<AppointmentImage> images) async {
    await Future.wait(images.map(deleteImage));
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}
