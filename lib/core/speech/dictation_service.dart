import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Field-level dictation over the platform speech recognizer.
///
/// One session at a time: starting a new session cancels the previous one and
/// fires its onSessionEnded. Injectable deps for tests (AuthService pattern).
class DictationService {
  DictationService({SpeechToText? speech, AppLogger? logger})
    : _speech = speech ?? SpeechToText(),
      _logger = logger ?? AppLogger();

  final SpeechToText _speech;
  final AppLogger _logger;

  bool? _available;
  VoidCallback? _onSessionEnded;

  Future<bool> _ensureInitialized() async {
    if (_available != null) return _available!;
    try {
      _available = await _speech.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );
    } catch (e, st) {
      _logger.warn('DICTATE initialize failed', e, st);
      _available = false;
    }
    return _available!;
  }

  /// Speech locale matching the app language, or null for the system default.
  Future<String?> localeIdFor(String languageCode) async {
    if (!await _ensureInitialized()) return null;
    try {
      final locales = await _speech.locales();
      for (final locale in locales) {
        if (locale.localeId.startsWith(languageCode)) return locale.localeId;
      }
    } catch (e, st) {
      _logger.warn('DICTATE locales lookup failed', e, st);
    }
    return null;
  }

  /// Starts listening; partial results stream through [onResult] with the full
  /// utterance so far. Returns false when the recognizer is unavailable.
  Future<bool> start({
    required void Function(String recognized, {required bool isFinal}) onResult,
    required VoidCallback onSessionEnded,
    String? localeId,
  }) async {
    if (!await _ensureInitialized()) return false;
    try {
      if (_speech.isListening) await _speech.cancel();
      _onSessionEnded?.call();
      _onSessionEnded = onSessionEnded;
      await _speech.listen(
        onResult: (result) =>
            onResult(result.recognizedWords, isFinal: result.finalResult),
        listenOptions: SpeechListenOptions(localeId: localeId),
      );
      return true;
    } catch (e, st) {
      _logger.warn('DICTATE listen failed', e, st);
      _onSessionEnded = null;
      return false;
    }
  }

  Future<void> stop() => _speech.stop();

  void _handleStatus(String status) {
    // A stale notListening can arrive just after a new listen() starts (from
    // cancelling the previous session) - the isListening guard ignores it.
    if (_speech.isListening) return;
    if (status == 'done' || status == 'notListening') {
      final ended = _onSessionEnded;
      _onSessionEnded = null;
      ended?.call();
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _logger.warn('DICTATE recognizer error ${error.errorMsg}');
  }
}

final dictationServiceProvider = Provider<DictationService>(
  (ref) => DictationService(),
);
