import 'package:scheduling/core/validators/password_requirements.dart';

/// Length at which the meter awards its fourth band. Advisory only — nothing
/// gates on it, unlike [PasswordRequirement.minLengthChars].
const int kStrongPasswordLength = 12;

/// 0–4 for the strength meter's segments. Display-only — the submit gate stays
/// [PasswordRequirement.allMetBy] via `AuthValidators.newPassword`, and this
/// must never drift into a second validator that can disagree with the
/// checklist rendered beside it.
///
/// Four bands, not five: mixed case counts as one bar, matching the design's
/// 4-segment meter. The fourth band is LENGTH, not a symbol — the symbol
/// requirement was removed (2026-08-21) and without a replacement band the
/// meter's "Strong" label became unreachable by any password the validator
/// accepts.
int passwordStrengthScore(String password) {
  var score = 0;
  if (PasswordRequirement.minLength.isMetBy(password)) score++;
  if (PasswordRequirement.uppercase.isMetBy(password) &&
      PasswordRequirement.lowercase.isMetBy(password)) {
    score++;
  }
  if (PasswordRequirement.number.isMetBy(password)) score++;
  if (password.length >= kStrongPasswordLength) score++;
  return score;
}
