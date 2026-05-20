import 'package:flutter/widgets.dart';
import 'package:scheduling/l10n/.gen/app_localizations.dart';

extension L10nBuildContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
