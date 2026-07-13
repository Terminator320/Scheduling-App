import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/speech/dictation_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Transient bar shown beneath a field while dictation is actively listening:
/// a live waveform, a "Listening…" label, and a Stop button. Stop ends the one
/// active dictation session via the service (single-session invariant), which
/// fires the session-ended callback that flips the host field back to idle.
class DictationListeningBar extends ConsumerWidget {
  const DictationListeningBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sp8),
      child: Container(
        padding: const EdgeInsets.only(
          left: AppSpacing.sp12,
          right: AppSpacing.sp4,
          top: AppSpacing.sp4,
          bottom: AppSpacing.sp4,
        ),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.r8),
        ),
        child: Row(
          children: [
            DictationWaveform(color: scheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.sp8),
            Expanded(
              child: Text(
                l10n.common_listening,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(dictationServiceProvider).stop(),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onPrimaryContainer,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sp12,
                ),
              ),
              child: Text(l10n.common_stop),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small row of animated bars suggesting live audio. Collapses to a static
/// mid-height row when the platform requests reduced motion.
class DictationWaveform extends StatefulWidget {
  const DictationWaveform({required this.color, super.key, this.barCount = 5});

  final Color color;
  final int barCount;

  @override
  State<DictationWaveform> createState() => _DictationWaveformState();
}

class _DictationWaveformState extends State<DictationWaveform>
    with SingleTickerProviderStateMixin {
  static const double _maxHeight = 16;
  static const double _minHeight = 4;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: _maxHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.barCount, (i) {
            final t = reduceMotion
                ? 0.5
                : 0.5 +
                      0.5 *
                          math.sin(
                            (_controller.value + i / widget.barCount) *
                                2 *
                                math.pi,
                          );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 3,
                height: _minHeight + (_maxHeight - _minHeight) * t,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
