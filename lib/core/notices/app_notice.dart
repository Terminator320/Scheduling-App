import 'package:flutter/foundation.dart';

@immutable
sealed class AppNotice {
  const AppNotice(this.message);
  final String message;

  const factory AppNotice.success(String message) = NoticeSuccess;
  const factory AppNotice.info(String message) = NoticeInfo;
  const factory AppNotice.error(String message) = NoticeError;
}

class NoticeSuccess extends AppNotice {
  const NoticeSuccess(super.message);
}

class NoticeInfo extends AppNotice {
  const NoticeInfo(super.message);
}

class NoticeError extends AppNotice {
  const NoticeError(super.message);
}
