import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon, required this.title, required this.body, super.key,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.r16),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 24, color: scheme.primary),
              ),
              const SizedBox(height: AppSpacing.sp16),
              Text(title, style: textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sp8),
              Text(
                body,
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.sp16),
                SizedBox(
                  width: 160,
                  child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
