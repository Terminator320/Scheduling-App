/// Individual password requirements for new passwords. Sign-in uses looser
/// rules, for backward compatibility with existing accounts.
enum PasswordRequirement {
  minLength,
  uppercase,
  lowercase,
  number;

  static const int minLengthChars = 8;

  static final RegExp _uppercase = RegExp(r'\p{Lu}', unicode: true);
  static final RegExp _lowercase = RegExp(r'\p{Ll}', unicode: true);
  static final RegExp _number = RegExp(r'\d');

  bool isMetBy(String password) => switch (this) {
    minLength => password.length >= minLengthChars,
    uppercase => _uppercase.hasMatch(password),
    lowercase => _lowercase.hasMatch(password),
    number => _number.hasMatch(password),
  };

  static bool allMetBy(String password) =>
      values.every((requirement) => requirement.isMetBy(password));
}
