import 'package:flutter/material.dart';

class AppFontScaleController extends ValueNotifier<double> {
  AppFontScaleController._() : super(1.0);

  static final AppFontScaleController instance = AppFontScaleController._();

  void setScale(double scale) {
    final normalized = scale.clamp(0.8, 1.4).toDouble();
    if ((normalized - value).abs() < 0.001) return;
    value = normalized;
  }

  void reset() => setScale(1.0);
}

class AppFontScaleScope extends InheritedNotifier<AppFontScaleController> {
  const AppFontScaleScope({
    super.key,
    required AppFontScaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppFontScaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppFontScaleScope>();
    return scope?.notifier ?? AppFontScaleController.instance;
  }
}
