import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

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

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
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
            child: builder(sheetContext, scrollController),
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
