import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageCompressService {
  // Keep uploaded appointment images large enough for viewing, but not full camera size.
  static const int maxCompressedDimension = 1600;

  Future<File> compressImage(File file) async {
    final dir = await getTemporaryDirectory();

    final targetPath = path.join(
      dir.path,
      "${DateTime.now().millisecondsSinceEpoch}.jpg",
    );

    final compressed = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70,
      minWidth: maxCompressedDimension,
      minHeight: maxCompressedDimension,
    );

    //fall back to original if compression fails
    if (compressed == null) {
      return file;
    }

    return File(compressed.path);
  }

  Future<List<File>> compressImages(List<File> files) async {
    final compressed = await Future.wait(files.map((f) => compressImage(f)));

    return compressed;
  }
}
