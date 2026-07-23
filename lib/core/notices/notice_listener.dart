import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (Color bg, Color fg, IconData icon) = switch (notice) {
      NoticeSuccess() => (
        theme.statusColors.successContainer,
        theme.statusColors.onSuccessContainer,
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

    // Native tactile cue alongside the visual notice (best-effort).
    unawaited(switch (notice) {
      NoticeError() => HapticFeedback.mediumImpact(),
      NoticeSuccess() || NoticeInfo() => HapticFeedback.lightImpact(),
    });

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
    // Pad left/right too so a landscape notch/camera cutout doesn't cover the text.
    final padding = MediaQuery.of(context).padding;
    // Push the banner toward the side with more safe-area room, away from the notch.
    final alignment = padding.left > padding.right
        ? Alignment.centerRight
        : padding.right > padding.left
        ? Alignment.centerLeft
        : Alignment.center;
    return Positioned(
      top: padding.top + 8,
      left: padding.left + AppSpacing.sp16,
      right: padding.right + AppSpacing.sp16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          // Cap the width so a landscape/tablet banner reads as a tidy card, not full-width.
          child: Align(
            alignment: alignment,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                liveRegion: true,
                // U5: swipe up to dismiss; Dismissible handles animation, so remove entry directly.
                child: Dismissible(
                  key: const ValueKey('app-notice-banner'),
                  direction: DismissDirection.up,
                  onDismissed: (_) => widget.onDismiss(),
                  child: Material(
                    color: widget.bg,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sp12,
                        AppSpacing.sp4,
                        AppSpacing.sp4,
                        AppSpacing.sp4,
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
                          const SizedBox(width: AppSpacing.sp4),
                          // U5: a real IconButton (48px tap target + tooltip/semantics), not a bare GestureDetector icon.
                          IconButton(
                            onPressed: _dismiss,
                            tooltip: context.l10n.common_close,
                            icon: Icon(Icons.close, color: widget.fg, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
