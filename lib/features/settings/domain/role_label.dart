import 'package:scheduling/l10n/l10n.dart';

/// Localized role label — shared by the settings drawer header and the
/// account-card role badge so the admin/employee wording stays in one place.
String roleLabel(AppLocalizations l10n, {required bool isAdmin}) =>
    isAdmin ? l10n.common_admin : l10n.common_employeeRoleValue;
