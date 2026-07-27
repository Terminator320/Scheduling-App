import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({
    required this.currentCode,
    required this.onChanged,
    super.key,
  });

  final String currentCode;
  final void Function(String code) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      padding: const EdgeInsets.all(3),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          _LangBtn(
            label: 'EN',
            isActive: currentCode == 'en',
            onTap: () => onChanged('en'),
          ),
          _LangBtn(
            label: 'FR',
            isActive: currentCode == 'fr',
            onTap: () => onChanged('fr'),
          ),
        ],
      ),
    );
  }
}

class _LangBtn extends StatelessWidget {
  const _LangBtn({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  /// Minimum tap-target side (Apple HIG / Material a11y): the old
  /// text-sized GestureDetector was ~24x17px and easy to miss.
  static const double _minTapTarget = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: isActive,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.r8),
          child: AnimatedContainer(
            duration: AppDuration.fast,
            constraints: const BoxConstraints(
              minWidth: _minTapTarget,
              minHeight: _minTapTarget,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp8),
            decoration: BoxDecoration(
              color: isActive ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.r8),
              boxShadow: isActive ? AppShadow.pill : null,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isActive ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
