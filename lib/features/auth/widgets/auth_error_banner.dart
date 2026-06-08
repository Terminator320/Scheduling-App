import 'package:flutter/material.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// Inline error banner for the auth forms: fade/size-animates an
/// error-container box in when [message] is non-null and collapses it when
/// cleared. Shared by the create-account and forgot-password screens.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({required this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = this.message;
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
              key: ValueKey('banner_$message'),
              padding: const EdgeInsets.only(top: AppSpacing.sp12),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sp12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: scheme.error, size: 16),
                    const SizedBox(width: AppSpacing.sp8),
                    Expanded(
                      child: Text(
                        message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
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
