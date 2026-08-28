import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notices/app_notice.dart';

class NoticeService {
  final StreamController<AppNotice> _controller =
      StreamController<AppNotice>.broadcast();
  bool _disposed = false;

  Stream<AppNotice> get stream => _controller.stream;

  void success(String message) => _emit(AppNotice.success(message));

  void info(String message) => _emit(AppNotice.info(message));

  void error(String message) => _emit(AppNotice.error(message));

  void _emit(AppNotice notice) {
    if (_disposed) return;
    _controller.add(notice);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.close();
  }
}

final noticeServiceProvider = Provider<NoticeService>((ref) {
  final service = NoticeService();
  ref.onDispose(service.dispose);
  return service;
});
