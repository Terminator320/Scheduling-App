import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/shared/widgets/primitives/app_back_button.dart';

/// The app's standard top bar: a primary-coloured [AppBar] with a bold
/// on-primary title, an optional back button ([onBack]) and optional
/// [actions] / [bottom].
///
/// Pass [compact] (typically `context.isLandscape`) to slim the toolbar and
/// shrink the title so the short landscape viewport keeps more room for
/// content. Use this on every screen instead of hand-building an [AppBar] so
/// the chrome stays consistent in one place.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    required this.title,
    super.key,
    this.onBack,
    this.actions,
    this.bottom,
    this.compact = false,
  });

  final String title;

  /// When non-null, a back arrow is shown as the leading widget.
  final VoidCallback? onBack;
  final List<Widget>? actions;

  /// A search bar, sub-header row, etc. — anything that implements
  /// [PreferredSizeWidget], rendered beneath the toolbar.
  final PreferredSizeWidget? bottom;

  /// Slims the toolbar + title for short (landscape) viewports.
  final bool compact;

  static const double _compactToolbarHeight = 44;

  @override
  Size get preferredSize => Size.fromHeight(
    (compact ? _compactToolbarHeight : kToolbarHeight) +
        (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    assert(
      compact == context.isLandscape,
      'AppTopBar.compact must equal context.isLandscape. '
      'Pass compact: context.isLandscape at the call site.',
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle =
        (compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)
            ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onPrimary);

    return AppBar(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      automaticallyImplyLeading: false,
      toolbarHeight: compact ? _compactToolbarHeight : null,
      leading: onBack == null ? null : AppBackButton(onTap: onBack!),
      title: Text(
        title,
        style: titleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}
