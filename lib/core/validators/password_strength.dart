import 'package:scheduling/core/validators/password_requirements.dart';

/// 0–4 for the strength meter's segments. Display-only — the submit gate stays
/// [PasswordRequirement.allMetBy] via `AuthValidators.newPassword`, and this
/// must never drift into a second validator that can disagree with the
/// checklist rendered beside it.
///
/// Four bands, not five: mixed case counts as one bar, matching the design's
/// 4-segment meter.
int passwordStrengthScore(String password) {
  var score = 0;
  if (PasswordRequirement.minLength.isMetBy(password)) score++;
  if (PasswordRequirement.uppercase.isMetBy(password) &&
      PasswordRequirement.lowercase.isMetBy(password)) {
    score++;
  }
  if (PasswordRequirement.number.isMetBy(password)) score++;
  if (PasswordRequirement.symbol.isMetBy(password)) score++;
  return score;
}
