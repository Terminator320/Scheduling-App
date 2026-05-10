import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';

/// Mounts under `MaterialApp.builder` so that every notice surfaces through
/// the root `ScaffoldMessenger`. Themed by `AppNotice` kind via
/// `Theme.of(context).colorScheme` (no static `AppColors.*` tokens).
class NoticeListener extends ConsumerStatefulWidget {
  const NoticeListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NoticeListener> createState() => _NoticeListenerState();
}

class _NoticeListenerState extends ConsumerState<NoticeListener> {
  StreamSubscription<AppNotice>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(noticeServiceProvider).stream.listen(_show);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _show(AppNotice notice) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final scheme = Theme.of(context).colorScheme;
    final accessible =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

    final (Color bg, Color fg, IconData icon) = switch (notice) {
      NoticeSuccess() => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      NoticeInfo() => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        Icons.info_outline,
      ),
      NoticeError() => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
    };

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: accessible ? 6 : 3),
          content: Semantics(
            liveRegion: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    notice.message,
                    style: TextStyle(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
