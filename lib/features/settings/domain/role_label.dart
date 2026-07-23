import 'package:scheduling/l10n/l10n.dart';

/// Localized role label, shared by settings drawer and account card.
String roleLabel(AppLocalizations l10n, {required bool isAdmin}) =>
    isAdmin ? l10n.common_admin : l10n.common_employeeRoleValue;
