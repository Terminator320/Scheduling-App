import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

bool _isShortSheetViewport(BuildContext context) =>
    MediaQuery.sizeOf(context).height < Breakpoints.shortViewportHeight;

class DraggableSheetFrame extends StatelessWidget {
  const DraggableSheetFrame({
    required this.builder,
    super.key,
    this.initialChildSize = 0.7,
    this.minChildSize = 0.5,
    this.maxChildSize = 0.95,
  });

  final ScrollableWidgetBuilder builder;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isShort = _isShortSheetViewport(context);

    return DraggableScrollableSheet(
      initialChildSize: isShort ? 0.82 : initialChildSize,
      minChildSize: isShort ? 0.58 : minChildSize,
      maxChildSize: isShort ? 0.98 : maxChildSize,
      expand: false,
      builder: (sheetContext, scrollController) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.r16),
              ),
              boxShadow: AppShadow.sheet,
            ),
            // A transparent Material sits between the decorated Container and
            // the sheet content so descendant ListTiles paint their background
            // and ink ripples here (above the Container's surface color) rather
            // than on the modal Material below, where the Container would hide
            // them.
            child: Material(
              type: MaterialType.transparency,
              child: builder(sheetContext, scrollController),
            ),
          ),
        );
      },
    );
  }
}

class SheetFocusScroll extends StatefulWidget {
  const SheetFocusScroll({required this.child, super.key});

  final Widget child;

  @override
  State<SheetFocusScroll> createState() => _SheetFocusScrollState();
}

class _SheetFocusScrollState extends State<SheetFocusScroll> {
  int _focusRequest = 0;

  Future<void> _ensureVisible(int request) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || request != _focusRequest) return;

    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      alignment: 0.3,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) _ensureVisible(++_focusRequest);
      },
      child: widget.child,
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(AppRadius.rFull),
        ),
      ),
    );
  }
}

/// Standard scrollable body for a detail view shown either in a bottom sheet
/// (with a drag [showHandle]) or a master-detail pane. Centralises the detail
/// padding and the keyboard-inset–aware bottom gap so every detail view stays
/// consistent.
class DetailSheetListView extends StatelessWidget {
  const DetailSheetListView({
    required this.children,
    super.key,
    this.scrollController,
    this.showHandle = false,
    this.bottomPadding = 24,
    this.handleGap = 16,
  });

  final List<Widget> children;
  final ScrollController? scrollController;
  final bool showHandle;
  final double bottomPadding;

  /// Gap between the drag handle and the first child (only when [showHandle]).
  final double handleGap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.only(
        left: AppSpacing.sp16,
        right: AppSpacing.sp16,
        top: AppSpacing.sp12,
        bottom: bottomInset + bottomPadding,
      ),
      children: [
        if (showHandle) ...[
          const SheetHandle(),
          SizedBox(height: handleGap),
        ],
        ...children,
      ],
    );
  }
}

/// Standard chrome for an add/edit **form** shown in a bottom sheet: the
/// [DraggableSheetFrame] container plus a scrollable body with the shared sheet
/// padding, a drag [SheetHandle], and a [headlineLarge] [title]. Put the
/// divider and form fields in [children]. Mirrors [DetailSheetListView], which
/// serves read-only detail views.
class FormSheetScaffold extends StatelessWidget {
  const FormSheetScaffold({
    required this.title,
    required this.children,
    super.key,
    this.initialChildSize = 0.7,
    this.minChildSize = 0.5,
    this.maxChildSize = 0.95,
  });

  final String title;
  final List<Widget> children;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  @override
  Widget build(BuildContext context) {
    final isShort = _isShortSheetViewport(context);
    return DraggableSheetFrame(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      builder: (sheetContext, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: AppSpacing.sp16,
            right: AppSpacing.sp16,
            top: AppSpacing.sp12,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.sp24,
          ),
          children: [
            const SheetHandle(),
            SizedBox(height: isShort ? AppSpacing.sp12 : AppSpacing.sp16),
            Text(
              title,
              style: isShort
                  ? Theme.of(sheetContext).textTheme.headlineSmall
                  : Theme.of(sheetContext).textTheme.headlineLarge,
            ),
            ...children,
          ],
        );
      },
    );
  }
}
