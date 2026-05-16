import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ImageCompressService {
  // Keep uploaded appointment images large enough for viewing, but not full camera size.
  static const int maxCompressedDimension = 1600;

  // WHY: parallel `Future.wait(files.map(compressImage))` calls were resolving
  // `DateTime.now()` in the same millisecond, producing identical targetPaths
  // and overwriting each other on disk — two picked photos uploaded as one.
  static int _seq = 0;

  Future<File> compressImage(File file) async {
    final dir = await getTemporaryDirectory();

    final unique = '${DateTime.now().millisecondsSinceEpoch}_${++_seq}';
    final targetPath = path.join(dir.path, '$unique.jpg');

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
    // Per-file try/catch so one bad input (IO error, plugin failure) doesn't
    // sink the whole batch. Falls back to the original file — the upload
    // service will filter it out if it exceeds the size cap.
    return Future.wait(
      files.map((f) async {
        try {
          return await compressImage(f);
        } catch (e, st) {
          debugPrint(
            '[ImageCompressService] compress failed for ${f.path}: $e',
          );
          debugPrintStack(stackTrace: st);
          return f;
        }
      }),
    );
  }
}
