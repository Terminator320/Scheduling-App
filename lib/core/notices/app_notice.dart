import 'dart:async';

import 'package:flutter/foundation.dart';

@immutable
sealed class AppNotice {
  const AppNotice(this.message, {this.action});

  const factory AppNotice.success(
    String message, {
    NoticeAction? action,
  }) = NoticeSuccess;
  const factory AppNotice.info(String message) = NoticeInfo;
  const factory AppNotice.error(String message) = NoticeError;
  final String message;
  final NoticeAction? action;
}

class NoticeSuccess extends AppNotice {
  const NoticeSuccess(super.message, {super.action});
}

class NoticeInfo extends AppNotice {
  const NoticeInfo(super.message);
}

class NoticeError extends AppNotice {
  const NoticeError(super.message);
}

@immutable
class NoticeAction {
  const NoticeAction({required this.label, required this.onPressed});

  final String label;
  final FutureOr<void> Function() onPressed;
}
