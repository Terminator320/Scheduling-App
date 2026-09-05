import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

/// Which slice of the typed number a result came back from.
enum PhoneRung { canonical, firstSeven, lastSeven }

/// One query the app is willing to send, and what it is.
typedef PhoneQueryRung = ({PhoneRung rung, String digits});

/// Shapes the query the app SENDS from the number the admin TYPES.
///
/// The token index holds every 3-12 digit substring at every start position,
/// so a slice of the typed number is a legal query and a far better one than
/// the raw string: it absorbs a leading country code and it survives a typo.
abstract final class PhoneQueryPolicy {
  const PhoneQueryPolicy._();

  /// Below this a digits-only query cannot be selective — `514` matches the
  /// roster twice over and costs 200 document reads to prove it.
  static const int minPhoneDigits = 7;

  static const int _nanpLength = 10;

  static final _letter = RegExp('[a-zA-Z]');

  static bool isPhoneQuery(String raw) =>
      !_letter.hasMatch(raw) && ClientSearchPolicy.digitsOnly(raw).isNotEmpty;

  static String canonicalDigits(String raw) {
    final digits = ClientSearchPolicy.digitsOnly(raw);
    if (digits.length == _nanpLength + 1 && digits.startsWith('1')) {
      return digits.substring(1);
    }
    return digits;
  }

  /// True once the number looks finished, so spending the fallback round trips
  /// is worth it. While he is still typing it stays false.
  static bool fallbacksAllowed(String raw) =>
      canonicalDigits(raw).length >= _nanpLength;

  /// The queries to try, in order, stopping at the first that answers.
  static List<PhoneQueryRung> ladder(String raw) {
    final digits = canonicalDigits(raw);
    if (digits.length < minPhoneDigits) return const [];

    final out = <PhoneQueryRung>[(rung: PhoneRung.canonical, digits: digits)];
    if (!fallbacksAllowed(raw)) return out;

    final seen = <String>{digits};
    void add(PhoneRung rung, String slice) {
      if (seen.add(slice)) out.add((rung: rung, digits: slice));
    }

    // Head first: a typo lands in the part of the number he is least sure of,
    // which is the tail, so the head is what survives it.
    add(PhoneRung.firstSeven, digits.substring(0, minPhoneDigits));
    add(PhoneRung.lastSeven, digits.substring(digits.length - minPhoneDigits));
    return out;
  }
}
