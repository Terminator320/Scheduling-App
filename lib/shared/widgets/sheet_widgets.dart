import 'package:flutter/material.dart';

class DraggableSheetFrame extends StatelessWidget {
  const DraggableSheetFrame({
    super.key,
    required this.builder,
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
      shouldCloseOnMinExtent: true,
      builder: (sheetContext, scrollController) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: builder(sheetContext, scrollController),
          ),
        );
      },
    );
  }
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: scheme.outlineVariant, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            color: theme.bottomSheetTheme.backgroundColor ?? theme.cardColor,
            child: child,
          ),
        ),
      ),
    );
  }
}

// Scrolls sheet form fields into view when the keyboard would otherwise cover them.
class SheetFocusScroll extends StatefulWidget {
  const SheetFocusScroll({super.key, required this.child});

  final Widget child;

  @override
  State<SheetFocusScroll> createState() => _SheetFocusScrollState();
}

class _SheetFocusScrollState extends State<SheetFocusScroll> {
  int _focusRequest = 0;

  Future<void> _ensureVisible(int request) async {
    // Let the keyboard animation start before calculating the field position.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || request != _focusRequest) return;

    // Keep the focused field comfortably above the keyboard.
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      alignment: 0.3,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        // Ignore older scroll requests if the user quickly taps another field.
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
        width: 48,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
