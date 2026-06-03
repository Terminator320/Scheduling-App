import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/l10n/l10n.dart';

sealed class ImageUploadFailure extends Failure {
  const ImageUploadFailure();
}

class ImageUploadFailureInvalidFormat extends ImageUploadFailure {
  const ImageUploadFailureInvalidFormat();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.error_somethingWentWrong;
}

class ImageUploadFailureTooLarge extends ImageUploadFailure {
  const ImageUploadFailureTooLarge();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.error_somethingWentWrong;
}
