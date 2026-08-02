import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/domain/signup_code_policy.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/features/auth/widgets/auth_form_widgets.dart';
import 'package:scheduling/features/auth/widgets/code_entry_boxes.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';

/// First half of the invite acceptance flow: the holder types the twelve
/// characters their admin read off the Team page, and `previewInvite` resolves
/// what the code was issued for before they invent a password.
///
/// The code is a credential — it lives in this screen's controller and rides
/// the route arguments to the details screen. It is never logged, never put in
/// a notice, and never written to storage.
class AcceptInviteCodeScreen extends ConsumerStatefulWidget {
  const AcceptInviteCodeScreen({
    this.initialCode = '',
    this.authService,
    super.key,
  });

  /// Prefilled by the deep-link dispatcher. A prefilled code arms the CTA but
  /// never auto-submits — a stale link would burn a preview slot for nothing
  /// the holder asked for.
  final String initialCode;

  final AuthService? authService;

  @override
  ConsumerState<AcceptInviteCodeScreen> createState() =>
      _AcceptInviteCodeScreenState();
}

class _AcceptInviteCodeScreenState
    extends ConsumerState<AcceptInviteCodeScreen> {
  late final AuthService _authService =
      widget.authService ?? ref.read(authServiceProvider);
  late final TextEditingController _codeController;

  bool _isLoading = false;
  String? _codeError;
  String? _bannerError;

  @override
  void initState() {
    super.initState();
    // The formatter only runs on user edits, so a prefilled code is normalized
    // here instead.
    _codeController = TextEditingController(
      text: normalizeSignupCode(widget.initialCode),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged(String _) {
    if (_codeError == null && _bannerError == null) {
      setState(() {});
      return;
    }
    setState(() {
      _codeError = null;
      _bannerError = null;
    });
  }

  Future<void> _continue() async {
    if (!isCompleteSignupCode(_codeController.text)) return;
    FocusScope.of(context).unfocus();

    // Fail fast before the flag: an awaited callable offline just spins until
    // the connection comes back.
    if (ref.read(isOfflineProvider)) {
      setState(() {
        _bannerError = const AuthFailureNetwork().toLocalizedMessageInContext(
          context,
          AuthErrorContext.register,
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _codeError = null;
      _bannerError = null;
    });

    final code = normalizeSignupCode(_codeController.text);
    try {
      final preview = await _authService.previewInvite(code);
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Push, never pushReplacement: back from the details screen has to land
      // here with the code still typed.
      await Navigator.of(context).pushNamed(
        AppRoutes.acceptInviteDetails,
        arguments: AcceptInviteDetailsArgs(code: code, preview: preview),
      );
    } catch (error, stackTrace) {
      final failure = AuthErrorMapper.map(error);
      ref
          .read(loggerProvider)
          .authFailure(
            'AUTH-PREVIEW previewInvite failed',
            failure,
            error,
            stackTrace,
          );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (failure is AuthFailureInvalidSignupCode) {
          _codeError = context.l10n.auth_codeInvalidExplanation;
        } else if (failure is AuthFailureSignupCodeExpired) {
          _codeError = context.l10n.auth_codeExpiredExplanation;
        } else {
          _bannerError = failure.toLocalizedMessageInContext(
            context,
            AuthErrorContext.register,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isComplete = isCompleteSignupCode(_codeController.text);
    final codeError = _codeError;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.auth_acceptInviteTitle,
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: AppSpacing.sp8),
          Text(
            l10n.auth_acceptInviteCodeSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sp24),
          DecoratedBox(
            decoration: appCardDecoration(
              theme,
              radius: AppRadius.r20,
              color: theme.colorScheme.surface,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sp16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CodeEntryBoxes(
                    controller: _codeController,
                    enabled: !_isLoading,
                    hasError: codeError != null,
                    onChanged: _onCodeChanged,
                    onSubmitted: _continue,
                  ),
                  if (codeError != null) ...[
                    const SizedBox(height: AppSpacing.sp12),
                    Center(
                      child: IntrinsicWidth(
                        child: AuthFieldError(message: codeError),
                      ),
                    ),
                  ],
                  AuthBanner(message: _bannerError),
                  const SizedBox(height: AppSpacing.sp16),
                  AnimatedLoadingButton(
                    label: isComplete
                        ? l10n.common_continue
                        : l10n.auth_enterTheCode,
                    isLoading: _isLoading,
                    onPressed: isComplete ? _continue : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sp24),
          const _NoCodePanel(),
        ],
      ),
    );
  }
}

/// The bordered help panel: there is no invite email in this program, so the
/// only recovery is the admin reading the code off the Team page.
class _NoCodePanel extends StatelessWidget {
  const _NoCodePanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sp16),
      decoration: BoxDecoration(
        color: theme.palette.lockedPanel,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: theme.palette.lockedPanelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MonoSectionLabel(context.l10n.auth_dontHaveACode),
          const SizedBox(height: AppSpacing.sp8),
          Text(
            context.l10n.auth_dontHaveACodeBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
