import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/employees/application/employee_form_controller.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
import 'package:scheduling/shared/widgets/feedback/user_status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';
import 'package:scheduling/shared/widgets/primitives/name_initials.dart';

/// The roster row for someone who has been invited but hasn't redeemed their
/// code yet. Tapping expands it in place — an invited person has no detail
/// page worth opening (no jobs, no availability that matters yet).
///
/// Expanding IS the reveal: it re-issues the invite and shows the fresh code.
/// The previous code stops working at that moment, which is why the caption
/// under the code always says the code is new.
class PendingInviteTile extends ConsumerStatefulWidget {
  const PendingInviteTile({required this.employee, super.key});

  final EmployeeRecord employee;

  @override
  ConsumerState<PendingInviteTile> createState() => _PendingInviteTileState();
}

class _PendingInviteTileState extends ConsumerState<PendingInviteTile> {
  bool _expanded = false;
  bool _copied = false;
  bool _resent = false;

  /// The signup code is a credential: it lives here and nowhere else. Never
  /// logged, never in a provider, never persisted, never in a notice.
  String? _code;

  /// Which invite [_code] belongs to. Re-expanding the SAME row must reuse the
  /// cached code instead of burning another of the admin's 20/hour slots (and
  /// silently rotating the code the admin already shared).
  String? _codeInviteId;

  String? get _cachedCode => _codeInviteId == widget.employee.id ? _code : null;

  Future<void> _toggleExpanded() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    if (next && _cachedCode == null) await _reissue(isResend: false);
  }

  /// Re-issues the invite through the idempotent `createEmployeeInvite` path.
  ///
  /// Every argument comes from the stored record: the callable's re-issue
  /// branch *updates* name/phone/colour/job title with whatever it is handed,
  /// so passing blanks would silently wipe the invited person's details.
  Future<void> _reissue({required bool isResend}) async {
    final l10n = context.l10n;
    final notices = ref.read(noticeServiceProvider);
    if (ref.read(employeeFormControllerProvider).isSaving) return;
    if (ref.read(isOfflineProvider)) {
      notices.error(
        composeErrorNotice(
          context,
          intro: l10n.error_introSaveEmployee,
          tag: 'EMP-CREATE',
          error: const SocketException('offline'),
        ),
      );
      return;
    }

    final employee = widget.employee;
    final outcome = await ref
        .read(employeeFormControllerProvider.notifier)
        .inviteEmployee(
          name: employee.name,
          firstName: employee.firstName,
          lastName: employee.lastName,
          email: employee.email,
          phone: employee.phone,
          colorValue: employee.color.toARGB32().toString(),
          jobTitle: employee.jobTitle.raw,
          isAdmin: employee.isAdmin,
        );
    if (!mounted) return;

    switch (outcome) {
      case EmployeeInvited(:final code):
        setState(() {
          _code = code;
          _codeInviteId = employee.id;
          _copied = false;
          _resent = isResend;
        });
      case EmployeeSaveFailed(:final error):
        notices.error(
          composeErrorNotice(
            context,
            intro: l10n.error_introSaveEmployee,
            tag: 'EMP-CREATE',
            error: error,
          ),
        );
      case EmployeeEmailInUse():
      case EmployeeUpdated():
        // Unreachable from a re-issue; the sealed family forces the branch.
        break;
    }
  }

  Future<void> _revoke() async {
    final l10n = context.l10n;
    final notices = ref.read(noticeServiceProvider);
    if (ref.read(employeeFormControllerProvider).isRevoking) return;
    if (ref.read(isOfflineProvider)) {
      notices.error(
        composeErrorNotice(
          context,
          intro: l10n.error_introRevokeInvite,
          tag: 'EMP-REVOKE',
          error: const SocketException('offline'),
        ),
      );
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: l10n.employees_revokeInvite,
      message: l10n.employees_revokeInviteConfirmBody,
      confirmLabel: l10n.employees_revokeInvite,
    );
    if (!confirmed || !mounted) return;

    final outcome = await ref
        .read(employeeFormControllerProvider.notifier)
        .revokeInvite(widget.employee.id);
    if (!mounted) return;

    switch (outcome) {
      case InviteRevoked():
        // No notice: the live stream drops the row, and that IS the
        // confirmation.
        break;
      case InviteRevokeFailed(:final error):
        notices.error(
          error is EmployeesFailureInviteNoLongerPending
              ? error.toLocalizedMessage(context)
              : composeErrorNotice(
                  context,
                  intro: l10n.error_introRevokeInvite,
                  tag: 'EMP-REVOKE',
                  error: error,
                ),
        );
    }
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(employeeFormControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        // AnimatedSize, not AnimatedCrossFade: the collapsed body must leave
        // the tree entirely, and a cross-fade keeps both children built — the
        // code would stay findable (and readable by a screen reader) on a
        // collapsed row.
        AnimatedSize(
          alignment: Alignment.topCenter,
          curve: Curves.easeOutCubic,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppDuration.normal,
          child: _expanded
              ? _buildBody(context, activity)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;
    final name = widget.employee.name.isEmpty ? '—' : widget.employee.name;
    const chip = UserStatusChip(status: UserStatus.invited);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleExpanded,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sp16,
            vertical: AppSpacing.sp12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashedAvatar(name: widget.employee.name),
              const SizedBox(width: AppSpacing.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.employee.email.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sp4),
                      Text(
                        widget.employee.email,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (compact) ...[
                      const SizedBox(height: AppSpacing.sp8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: chip,
                      ),
                    ],
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: AppSpacing.sp8),
                chip,
              ],
              const SizedBox(width: AppSpacing.sp8),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppDuration.fast,
                child: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, EmployeeFormActivity activity) {
    final l10n = context.l10n;
    final code = _cachedCode;
    final expiresAt = widget.employee.codeExpiresAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        0,
        AppSpacing.sp16,
        AppSpacing.sp16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MonoSectionLabel(l10n.employees_inviteCodeKey),
          const SizedBox(height: AppSpacing.sp8),
          _CodeBlock(
            code: code,
            isBusy: activity.isSaving,
            copied: _copied,
            onCopy: code == null ? null : () => _copy(code),
            onShow: () => _reissue(isResend: false),
          ),
          if (code != null) ...[
            const SizedBox(height: AppSpacing.sp8),
            // The code was minted the moment this row opened, so the caption
            // always says so — the admin's previously-shared code is dead.
            if (expiresAt != null)
              _NewCodeCaption(expiresAt: expiresAt)
            else
              // No stamp yet (a pre-P4b invite, or the stream hasn't caught
              // up): the expiry line is omitted rather than faked.
              Text(
                l10n.employees_newCodeIssued,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).palette.textMuted,
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sp16),
          _ActionRow(
            resendLabel: _resent
                ? l10n.employees_newCodeReady
                : l10n.employees_resendCode,
            onResend: activity.isSaving ? null : () => _reissue(isResend: true),
            onRevoke: activity.isRevoking ? null : _revoke,
            isRevoking: activity.isRevoking,
          ),
        ],
      ),
    );
  }
}

/// The `INVITE CODE` block: the fresh code plus its Copy pill, a spinner while
/// the re-issue is in flight, or a retry button when it never landed (offline,
/// or a failed call).
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.code,
    required this.isBusy,
    required this.copied,
    required this.onCopy,
    required this.onShow,
  });

  final String? code;
  final bool isBusy;
  final bool copied;
  final VoidCallback? onCopy;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    Widget child;
    final value = code;
    if (value != null) {
      final label = copied ? l10n.common_copied : l10n.employees_copyCode;
      final codeText = SelectableText(
        value,
        style: theme.monoType.data.copyWith(
          fontSize: 19,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
        ),
      );
      final copyButton = TextButton.icon(
        onPressed: copied ? null : onCopy,
        icon: Icon(
          copied ? Icons.check_rounded : Icons.copy_outlined,
          size: 18,
        ),
        label: Text(label),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      );
      child = context.isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                codeText,
                const SizedBox(height: AppSpacing.sp8),
                copyButton,
              ],
            )
          : Row(
              children: [
                Expanded(child: codeText),
                const SizedBox(width: AppSpacing.sp8),
                copyButton,
              ],
            );
    } else if (isBusy) {
      child = const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.sp12),
          child: AdaptiveProgressIndicator(),
        ),
      );
    } else {
      child = Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onShow,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: Text(l10n.employees_showCode),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp12,
        vertical: AppSpacing.sp8,
      ),
      decoration: BoxDecoration(
        color: theme.palette.sheetRow,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: child,
    );
  }
}

/// Amber caption stating the code is new and when it dies. Warning-toned on
/// purpose: opening the row invalidated whatever the admin shared before.
class _NewCodeCaption extends StatelessWidget {
  const _NewCodeCaption({required this.expiresAt});

  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.statusColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp12,
        vertical: AppSpacing.sp8,
      ),
      decoration: BoxDecoration(
        color: status.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Text(
        context.l10n.employees_newCodeExpiresOn(
          DateUtilsHelper.formatDate(expiresAt),
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: status.onWarningContainer,
        ),
      ),
    );
  }
}

/// Resend and Revoke as two equal-width bordered actions, stacking when the
/// row is too narrow or the text too large to hold them side by side.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.resendLabel,
    required this.onResend,
    required this.onRevoke,
    required this.isRevoking,
  });

  final String resendLabel;
  final VoidCallback? onResend;
  final VoidCallback? onRevoke;
  final bool isRevoking;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const minimumSize = Size.fromHeight(48);

    final resend = OutlinedButton(
      onPressed: onResend,
      style: OutlinedButton.styleFrom(minimumSize: minimumSize),
      child: Text(
        resendLabel,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final revoke = OutlinedButton(
      onPressed: onRevoke,
      style: destructiveOutlinedButtonStyle(context, minimumSize: minimumSize),
      child: isRevoking
          ? const AdaptiveProgressIndicator(size: 18)
          : Text(
              l10n.employees_revokeInvite,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
    );

    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          resend,
          const SizedBox(height: AppSpacing.sp8),
          revoke,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: resend),
        const SizedBox(width: AppSpacing.sp8),
        Expanded(child: revoke),
      ],
    );
  }
}

/// Dashed-ring avatar — the visual cue that this person hasn't joined yet. No
/// crew colour is rendered even though the invite HAS reserved one: the
/// dashing is visual only, and `usedColors` still counts the invite.
class _DashedAvatar extends StatelessWidget {
  const _DashedAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.palette;
    final initials = nameInitials(name);
    final diameter = AvatarSize.md.diameter;
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _DashedCirclePainter(color: palette.decorFaint),
        child: Center(
          child: initials == '?'
              ? Icon(Icons.person_outline, size: 17, color: palette.textMuted)
              : Text(
                  initials,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color});

  final Color color;

  static const int _dashCount = 12;
  static const double _strokeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    final rect = Rect.fromLTWH(
      _strokeWidth / 2,
      _strokeWidth / 2,
      size.width - _strokeWidth,
      size.height - _strokeWidth,
    );
    const sweep = 2 * math.pi / _dashCount;
    for (var i = 0; i < _dashCount; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
