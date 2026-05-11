import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/image_compress_service.dart';
import 'package:scheduling/core/images/image_picker_service.dart';
import 'package:scheduling/core/images/image_storage_service.dart';

/// Picks raw images from the camera roll / camera, downsized to a sane
/// maximum dimension before they reach compression.
final imagePickerProvider = Provider<ImagePickerService>(
  (ref) => ImagePickerService(),
);

/// Re-encodes picked images at lower JPEG quality so uploads stay under the
/// Firebase Storage size cap.
final imageCompressProvider = Provider<ImageCompressService>(
  (ref) => ImageCompressService(),
);

/// Validates magic bytes (JPEG `FF D8 FF` / PNG `89 50 4E`) and uploads to
/// Firebase Storage. The magic-byte check is a CLAUDE.md security invariant.
final imageStorageProvider = Provider<ImageStorageService>(
  (ref) => ImageStorageService(),
);
