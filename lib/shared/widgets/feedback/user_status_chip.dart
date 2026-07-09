import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_pill.dart';

/// The account lifecycle for a `users`/employee doc: an [invited] account that
/// has not yet redeemed its signup code, an [active] one, or a [disabled] one.
/// Appointment lifecycle states live in `AppointmentStatus` (status_chip.dart).
enum UserStatus {
  active,
  invited,
  disabled;

  /// Canonical mapping from a stored user/account status string; anything that
  /// isn't an explicit `active`/`disabled` (including a not-yet-redeemed
  /// invite's `invited`/empty status) falls through to [invited].
  static UserStatus fromRaw(String raw) => switch (raw.toLowerCase()) {
    'active' => active,
    'disabled' => disabled,
    _ => invited,
  };
}

/// Localized label for a user/account status.
String userStatusLabel(AppLocalizations l10n, UserStatus status) =>
    switch (status) {
      UserStatus.active => l10n.status_active,
      UserStatus.invited => l10n.status_invited,
      UserStatus.disabled => l10n.status_disabled,
    };

class UserStatusChip extends StatelessWidget {
  const UserStatusChip({required this.status, super.key});
  final UserStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = _colorsFor(theme.colorScheme, theme.statusColors);
    return StatusPill(
      label: userStatusLabel(context.l10n, status),
      background: bg,
      foreground: fg,
    );
  }

  (Color, Color) _colorsFor(ColorScheme scheme, AppStatusColors statusColors) =>
      switch (status) {
        UserStatus.active => (
          statusColors.successContainer,
          statusColors.onSuccessContainer,
        ),
        UserStatus.invited => (
          statusColors.invitedContainer,
          statusColors.onInvitedContainer,
        ),
        UserStatus.disabled => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      };
}
