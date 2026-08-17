// Pins the compound layout getters. They gate chrome app-wide, and the
// codebase already carries one regression from exactly this shape: a gate
// written as `> 1.4` missed the in-app XL text setting, which is EXACTLY 1.4.
//
// The two thresholds are deliberately different questions and must not be
// conflated: isSplitLayout is "wide OR landscape" (calendar chrome) while
// isTwoPane is shortest-side only (list master-detail), so a landscape phone
// reports the first and not the second.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/layout/breakpoints.dart';

/// Reads the getters under a forced size and text scale.
Future<
  ({
    bool isWide,
    bool isLandscape,
    bool isSplitLayout,
    bool isTwoPane,
    bool isCompact,
    bool isNarrowWidth,
  })
>
_read(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  late final BuildContext ctx;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return (
    isWide: ctx.isWide,
    isLandscape: ctx.isLandscape,
    isSplitLayout: ctx.isSplitLayout,
    isTwoPane: ctx.isTwoPane,
    isCompact: ctx.isCompact,
    isNarrowWidth: ctx.isNarrowWidth,
  );
}

void main() {
  testWidgets('a portrait phone is neither split nor two-pane', (tester) async {
    final r = await _read(tester, size: const Size(390, 844));

    expect(r.isWide, isFalse);
    expect(r.isLandscape, isFalse);
    expect(r.isSplitLayout, isFalse);
    expect(r.isTwoPane, isFalse);
  });

  testWidgets('a landscape phone splits but never opens a second pane', (
    tester,
  ) async {
    // The distinction that matters: it IS landscape, so the calendar goes
    // side-by-side, but its shortest side is too narrow for a detail pane.
    final r = await _read(tester, size: const Size(844, 390));

    expect(r.isLandscape, isTrue);
    expect(r.isSplitLayout, isTrue);
    expect(r.isTwoPane, isFalse);
  });

  testWidgets('a portrait tablet is two-pane without being landscape', (
    tester,
  ) async {
    final r = await _read(tester, size: const Size(834, 1194));

    expect(r.isLandscape, isFalse);
    expect(r.isTwoPane, isTrue);
  });

  testWidgets('isWide is inclusive at the tablet threshold', (tester) async {
    expect(
      (await _read(tester, size: const Size(Breakpoints.tablet, 1200))).isWide,
      isTrue,
    );
    expect(
      (await _read(
        tester,
        size: const Size(Breakpoints.tablet - 1, 1200),
      )).isWide,
      isFalse,
    );
  });

  testWidgets('isTwoPane is inclusive at the shortest-side threshold', (
    tester,
  ) async {
    expect(
      (await _read(
        tester,
        size: const Size(1000, Breakpoints.tabletShortestSide),
      )).isTwoPane,
      isTrue,
    );
    expect(
      (await _read(
        tester,
        size: const Size(1000, Breakpoints.tabletShortestSide - 1),
      )).isTwoPane,
      isFalse,
    );
  });

  testWidgets('isCompact fires on a narrow screen at normal text', (
    tester,
  ) async {
    final r = await _read(tester, size: const Size(320, 640));

    expect(r.isCompact, isTrue);
    expect(r.isNarrowWidth, isTrue);
  });

  testWidgets('isCompact fires on large text at a normal width', (
    tester,
  ) async {
    final r = await _read(tester, size: const Size(390, 844), textScale: 1.6);

    expect(r.isCompact, isTrue);
    // Width-only, so this one must NOT follow the text scale.
    expect(r.isNarrowWidth, isFalse);
  });

  testWidgets('the in-app XL scale sits exactly ON the boundary', (
    tester,
  ) async {
    // The in-app XL setting is 1.4 and the gate is `>`, so XL alone does NOT
    // compact. This is the documented historical regression: a call site that
    // assumed XL compacts was wrong, and one that assumes it never will is
    // wrong too — pin the actual boundary rather than either belief.
    expect(
      (await _read(
        tester,
        size: const Size(390, 844),
        textScale: Breakpoints.compactTextScale,
      )).isCompact,
      isFalse,
    );
    expect(
      (await _read(
        tester,
        size: const Size(390, 844),
        textScale: Breakpoints.compactTextScale + 0.01,
      )).isCompact,
      isTrue,
    );
  });
}
