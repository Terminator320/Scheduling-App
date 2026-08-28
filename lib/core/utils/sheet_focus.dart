import 'package:flutter/widgets.dart';

abstract final class SheetFocus {
  static Future<void> settleBeforeSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  static Future<void> unfocusAfterSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    FocusManager.instance.primaryFocus?.unfocus();
  }
}
