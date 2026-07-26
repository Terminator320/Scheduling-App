import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_pill.dart';

/// Account states: invited (not yet redeemed), active, or disabled.
enum UserStatus {
  active,
  invited,
  disabled;

  /// Maps a stored status. Anything not explicitly recognized falls through
  /// to invited.
  static UserStatus fromRaw(String raw) => switch (raw.toLowerCase()) {
    'active' => active,
    'disabled' => disabled,
    _ => invited,
  };
}

/// Localized account status label.
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
