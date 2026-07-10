import 'dart:async';

class SettingsSaveDebouncer {
  SettingsSaveDebouncer({this.delay = const Duration(milliseconds: 250)});

  final Duration delay;
  Timer? _timer;

  void run(Future<void> Function() save) {
    _timer?.cancel();
    _timer = Timer(delay, save);
  }

  void dispose() {
    _timer?.cancel();
  }
}
