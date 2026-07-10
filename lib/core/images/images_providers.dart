import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/image_picker_service.dart';
import 'package:scheduling/core/images/image_storage_service.dart';

final imagePickerProvider = Provider<ImagePickerService>(
  (ref) => ImagePickerService(),
);

final imageStorageProvider = Provider<ImageStorageService>(
  (ref) => ImageStorageService(),
);
