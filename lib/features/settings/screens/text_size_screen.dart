import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';

class TextSizeScreen extends StatefulWidget {
  const TextSizeScreen({super.key});

  @override
  State<TextSizeScreen> createState() => _TextSizeScreenState();
}

class _TextSizeScreenState extends State<TextSizeScreen> {
  static const _options = [
    ('Small', 0.8),
    ('Medium', 1.0),
    ('Large', 1.2),
    ('Extra Large', 1.4),
  ];

  late double _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected = ThemeNotifier.of(context).textScale;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l10n.textSize,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: [
          // Preview card
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PREVIEW',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sp12),
                MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(_selected)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appointment Title',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Tuesday, May 12 · 9:00 – 9:45 AM',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Sarah Johnson · 514-555-0101',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sp12),

          // Size options
          _Card(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Column(
              children: [
                for (int i = 0; i < _options.length; i++) ...[
                  _SizeRow(
                    label: _options[i].$1,
                    scale: _options[i].$2,
                    isSelected: (_selected - _options[i].$2).abs() < 0.01,
                    onTap: () => setState(() => _selected = _options[i].$2),
                  ),
                  if (i < _options.length - 1)
                    const Divider(height: 1, indent: 52),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Applies across the entire app',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sp24),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.r12),
              ),
            ),
            onPressed: () {
              ThemeNotifier.of(context).setTextScale(_selected);
              Navigator.pop(context);
            },
            child: Text(
              context.l10n.apply,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        boxShadow: isDark ? null : AppShadow.card,
        border: isDark ? Border.all(color: scheme.outlineVariant) : null,
      ),
      padding: padding ?? const EdgeInsets.all(14),
      child: child,
    );
  }
}

// ── Size Row ──────────────────────────────────────────────────────────────────

class _SizeRow extends StatelessWidget {
  const _SizeRow({
    required this.label,
    required this.scale,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final double scale;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r8),
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.r8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: 11 + (scale - 0.8) * 16,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? scheme.primary : null,
                  fontSize: 15,
                ),
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
