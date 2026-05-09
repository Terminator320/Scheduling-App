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
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l10n.textSize,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: [
          // Preview card
          _SectionCard(
            children: [
              Text(
                'Preview',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sp12),
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(_selected),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appointment Title',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Tuesday, May 12 · 9:00 – 9:45 AM',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sarah Johnson · 514-555-0101',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sp12),

          // Size options card
          _SectionCard(
            children: [
              for (int i = 0; i < _options.length; i++) ...[
                _SizeRow(
                  label: _options[i].$1,
                  scale: _options[i].$2,
                  isSelected: (_selected - _options[i].$2).abs() < 0.01,
                  isLast: i == _options.length - 1,
                  onTap: () => setState(() => _selected = _options[i].$2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Applies across the entire app',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sp24),

          FilledButton(
            onPressed: () {
              ThemeNotifier.of(context).setTextScale(_selected);
              Navigator.pop(context);
            },
            child: Text(context.l10n.apply),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SizeRow extends StatelessWidget {
  const _SizeRow({
    required this.label,
    required this.scale,
    required this.isSelected,
    required this.isLast,
    required this.onTap,
  });

  final String label;
  final double scale;
  final bool isSelected;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: isLast
            ? null
            : const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.outline),
                ),
              ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: 12 + (scale - 0.8) * 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.check,
              size: 16,
              color: isSelected ? AppColors.primary : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
