import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../models/appointmentImage.dart';

class ImageStorageService {
  final CloudinaryPublic _cloudinary = CloudinaryPublic(
    dotenv.env['CLOUDINARY_CLOUD_NAME']!,
    dotenv.env['CLOUDINARY_UPLOAD_PRESET']!,
    cache: false,
  );

  Future<AppointmentImage> uploadImage(File file) async {
    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          resourceType: CloudinaryResourceType.Image,
          folder: 'events',
        ),
      );

      return AppointmentImage(
        url: response.secureUrl,
        publicId: response.publicId,
        thumbUrl: _buildThumbUrl(response.secureUrl),
        fileName: file.uri.pathSegments.last,
        uploadedAt: Timestamp.now(),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<List<AppointmentImage>> uploadImages(List<File> files) async {
    final images = await Future.wait(files.map((f) => uploadImage(f)));
    return images;
  }

  String _buildThumbUrl(String secureUrl) {
    const marker = '/upload/';
    final i = secureUrl.indexOf(marker);
    if (i == -1) return secureUrl;
    return '${secureUrl.substring(0, i + marker.length)}w_200,h_200,c_fill,q_auto,f_auto/${secureUrl.substring(i + marker.length)}';
  }
}
