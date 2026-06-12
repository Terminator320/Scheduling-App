import 'package:flutter/material.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// Whether an [AuthBanner] shows a failure (error colors) or a confirmation
/// (green success tokens).
enum AuthBannerKind { error, success }

/// Inline status banner for the auth forms: fade/size-animates a colored box
/// in when [message] is non-null and collapses it when cleared. Shared by all
/// three auth screens — sign-in uses both kinds, the others only the
/// error kind.
class AuthBanner extends StatelessWidget {
  const AuthBanner({
    required this.message,
    this.kind = AuthBannerKind.error,
    super.key,
  });

  final String? message;
  final AuthBannerKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.statusColors;
    final message = this.message;
    final isError = kind == AuthBannerKind.error;
    final background = isError
        ? scheme.errorContainer
        : status.successContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : status.onSuccessContainer;
    final accent = isError ? scheme.error : status.success;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;

    return AnimatedSwitcher(
      duration: AppAnimationDurations.banner,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: AlignmentDirectional.topStart,
          child: child,
        ),
      ),
      child: message == null
          ? const SizedBox.shrink(key: ValueKey('banner_none'))
          : Padding(
              key: ValueKey('banner_${kind.name}_$message'),
              padding: const EdgeInsets.only(top: AppSpacing.sp12),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sp12),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: accent, size: 16),
                    const SizedBox(width: AppSpacing.sp8),
                    Expanded(
                      child: Text(
                        message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
