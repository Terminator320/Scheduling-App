import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

class NoticeListener extends ConsumerStatefulWidget {
  const NoticeListener({required this.child, this.navigatorKey, super.key});

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  ConsumerState<NoticeListener> createState() => _NoticeListenerState();
}

class _NoticeListenerState extends ConsumerState<NoticeListener> {
  StreamSubscription<AppNotice>? _sub;
  OverlayEntry? _currentEntry;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(noticeServiceProvider).stream.listen(_show);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;
    super.dispose();
  }

  void _show(AppNotice notice) {
    if (!mounted) return;
    final overlay =
        widget.navigatorKey?.currentState?.overlay ?? Overlay.maybeOf(context);
    if (overlay == null) return;

    final accessible =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    final duration = Duration(seconds: accessible ? 6 : 3);
    final scheme = Theme.of(context).colorScheme;

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

    _currentEntry?.remove();
    _currentEntry = null;

    late final OverlayEntry entry;
    var dismissed = false;

    void dismiss() {
      if (dismissed) return;
      dismissed = true;
      entry.remove();
      if (_currentEntry == entry) _currentEntry = null;
    }

    entry = OverlayEntry(
      builder: (_) => _TopNotice(
        bg: bg,
        fg: fg,
        icon: icon,
        message: notice.message,
        duration: duration,
        onDismiss: dismiss,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TopNotice extends StatefulWidget {
  const _TopNotice({
    required this.bg,
    required this.fg,
    required this.icon,
    required this.message,
    required this.duration,
    required this.onDismiss,
  });

  final Color bg;
  final Color fg;
  final IconData icon;
  final String message;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_TopNotice> createState() => _TopNoticeState();
}

class _TopNoticeState extends State<_TopNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimationDurations.banner,
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: AppAnimationCurves.entrance,
          ),
        );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();
    Future.delayed(widget.duration, () {
      if (mounted) _dismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: AppSpacing.sp16,
      right: AppSpacing.sp16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Semantics(
            liveRegion: true,
            child: Material(
              color: widget.bg,
              borderRadius: BorderRadius.circular(AppRadius.r12),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sp12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: widget.fg, size: 20),
                    const SizedBox(width: AppSpacing.sp12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(color: widget.fg, fontSize: 14),
                      ),
                    ),
                    GestureDetector(
                      onTap: _dismiss,
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sp8),
                        child: Icon(Icons.close, color: widget.fg, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
