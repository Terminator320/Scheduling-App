import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/permissions/media_permission_service.dart';
import 'package:scheduling/core/speech/dictation_service.dart';
import 'package:scheduling/core/speech/dictation_text_merge.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Suffix-slot dictation mic for a text field. Tapping it (after the
/// microphone permission gate) streams live speech into [controller] at the
/// caret captured when dictation started; tapping again stops.
///
/// Its listening state drives [listening] when provided, so the host field can
/// render a live listening bar in sync. When [listening] is null the button
/// owns an internal notifier (standalone use).
class DictationMicButton extends ConsumerStatefulWidget {
  const DictationMicButton({
    required this.controller,
    super.key,
    this.onChanged,
    this.maxLength,
    this.listening,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final int? maxLength;
  final ValueNotifier<bool>? listening;

  @override
  ConsumerState<DictationMicButton> createState() => _DictationMicButtonState();
}

class _DictationMicButtonState extends ConsumerState<DictationMicButton> {
  ValueNotifier<bool>? _internal;
  bool _isStarting = false;
  String _baseText = '';
  int _insertAt = 0;
  // Cached in _start so dispose can stop the session without touching `ref`
  // (reading a provider during unmount is unsafe).
  DictationService? _service;

  ValueNotifier<bool> get _listening => widget.listening ?? _internal!;

  @override
  void initState() {
    super.initState();
    if (widget.listening == null) _internal = ValueNotifier(false);
  }

  @override
  void dispose() {
    if (_listening.value) _service?.stop();
    _internal?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_isStarting) return;
    _isStarting = true;
    try {
      final permission = await ref
          .read(mediaPermissionServiceProvider)
          .ensureMicrophone();
      if (!mounted) return;
      if (permission != MediaPermissionResult.granted) {
        ref
            .read(noticeServiceProvider)
            .error(
              permission == MediaPermissionResult.permanentlyDenied
                  ? context.l10n.error_microphonePermissionPermanentlyDenied
                  : context.l10n.error_microphonePermissionDenied,
            );
        return;
      }
      final service = ref.read(dictationServiceProvider);
      _service = service;
      final localeId = await service.localeIdFor(
        Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      _baseText = widget.controller.text;
      final selection = widget.controller.selection;
      _insertAt = selection.isValid ? selection.end : _baseText.length;
      final started = await service.start(
        localeId: localeId,
        onResult: _applyResult,
        onSessionEnded: _handleSessionEnded,
      );
      if (!mounted) return;
      if (!started) {
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.error_dictationUnavailable);
        return;
      }
      _listening.value = true;
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _stop() {
    final DictationService service =
        _service ?? ref.read(dictationServiceProvider);
    return service.stop();
  }

  void _applyResult(String recognized, {required bool isFinal}) {
    final merged = mergeDictation(
      base: _baseText,
      insertAt: _insertAt,
      recognized: recognized,
      maxLength: widget.maxLength,
    );
    widget.controller.value = TextEditingValue(
      text: merged.text,
      selection: TextSelection.collapsed(offset: merged.caret),
    );
    widget.onChanged?.call(merged.text);
  }

  void _handleSessionEnded() {
    if (mounted) _listening.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: _listening,
      builder: (context, listening, _) => IconButton(
        icon: Icon(
          listening ? Icons.mic : Icons.mic_none,
          size: 16,
          color: listening ? scheme.primary : scheme.onSurfaceVariant,
        ),
        tooltip: listening
            ? context.l10n.common_stopDictation
            : context.l10n.common_dictate,
        onPressed: listening ? _stop : _start,
      ),
    );
  }
}
