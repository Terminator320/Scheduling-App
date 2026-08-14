/// The stored/displayed split for a client's name.
///
/// **`clients/{id}.name` IS THE WAVE CUSTOMER NAME**, and as of 2026-08-14
/// (owner call) that means two different things depending on who the client
/// is. The field is synced VERBATIM by `toWaveCustomerInput`
/// (`functions/wave/mappers.js`), and it is what shows on Wave's customer list
/// and on an invoice.
///
/// - **A PERSON is named by their phone number**: "(514) 555-1234". That is
///   what the invoicing workflow identifies them by. Their real name lives in
///   `firstName`/`lastName`, so nothing is lost.
/// - **A BUSINESS keeps its name**: "3101-5696 qc inc.", "1505 Village de
///   Bergerac". That name is the identity; a number in its place would make
///   the customer unrecognisable, and there is rarely a first/last to fall
///   back on. [ClientNamePolicy.looksLikeBusinessName] is what catches the
///   Wave-imported ones, which carry no `type`.
///
/// **The app never renders `name` for a person.** Every in-app surface reads
/// `ClientRecord.displayName` → [ClientNamePolicy.displayFor]: the first/last
/// halves for a person, the business name for a business — so a card, a search
/// result, an avatar's initials and the `clientName` denormalized onto an
/// appointment all say "Marc Tremblay" or "Vogas Plumbing".
///
/// [ClientNamePolicy.stripPhone] survives for the legacy shape — a stored name
/// that still carries `"<name> <number>"` — and is what the edit sheet seeds
/// from. [ClientNamePolicy.composeStored] is idempotent on both branches,
/// which is what lets the backfill and every ordinary save re-run safely.
///
/// **Hand-mirrored in `functions/client_name_utils.js`** (which
/// `propagateClientEdits` and the backfill script both read through). The two
/// share worked examples in their tests — change them together.
library;

import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';

class ClientNamePolicy {
  const ClientNamePolicy._();

  static final _nonDigit = RegExp(r'\D');

  /// A run of digits and the separators a person types between them, ANYWHERE
  /// in the string. The `\d` at each end keeps a trailing "(" or "-" out of the
  /// match.
  ///
  /// Only ever acted on when it reduces to a clean 10-digit number — see
  /// [extractPhone].
  static final _candidate = RegExp(r'\+?\d[\d\s().\-]{7,}\d');

  /// A phone-shaped run anchored to the END of the string, with whatever
  /// separator was typed in front of it. Deliberately loose — a match is only
  /// ever ACTED on when its digits equal the doc's own stored number, so this
  /// cannot mistake a street number, a postal code or a year for a phone.
  static final _trailingPhone = RegExp(
    r'[\s,;:\-–—·|]*(\+?\d[\d\s().+\-]{5,}\d)\s*$',
  );

  /// Separator runs at either end. Leading matters for [liftPhoneFromName],
  /// where the number can sit at the FRONT ("514-555-1234 - Marc Tremblay").
  static final _edgeSeparators = RegExp(r'^[\s,;:\-–—·|]+|[\s,;:\-–—·|]+$');

  /// The doc's number reduced to comparable digits. A NANP number typed with
  /// its leading country code ("1-514-555-1234") is the same number as
  /// "(514) 555-1234", so the 11-digit form sheds its leading 1.
  static String _digits(String value) {
    final digits = value.replaceAll(_nonDigit, '');
    if (digits.length == 11 && digits.startsWith('1')) {
      return digits.substring(1);
    }
    return digits;
  }

  static String _trimSeparators(String value) =>
      value.replaceAll(_edgeSeparators, '').trim();

  /// [name] with the client's own trailing phone number removed.
  ///
  /// Returns [name] unchanged when the trailing run is not this client's
  /// number — that is what keeps a business genuinely named with digits
  /// ("Depanneur 2000") intact.
  ///
  /// Returns `''` when the name is nothing BUT the number; callers decide what
  /// to show instead ([displayFor] falls back to the first/last halves).
  static String stripPhone(
    String name, {
    String phone = '',
    String mobile = '',
  }) {
    final base = name.trim();
    if (base.isEmpty) return '';

    // Exact suffix first. This is the shape [composeStored] writes, so an
    // app-written name round-trips losslessly whatever the number looks like —
    // including the international and extension forms `PhoneInputFormatter`
    // deliberately passes through unmasked.
    for (final candidate in [phone.trim(), mobile.trim()]) {
      if (candidate.isEmpty) continue;
      if (base.endsWith(candidate)) {
        return _trimSeparators(
          base.substring(0, base.length - candidate.length),
        );
      }
    }

    // Digit-matched trailing run. Legacy docs were typed with the number in a
    // different shape from the stored one ("Marc Tremblay 514-555-1234" beside
    // a stored "(514) 555-1234"), so an exact suffix misses them.
    final wanted = <String>{
      for (final candidate in [phone, mobile])
        if (_digits(candidate).isNotEmpty) _digits(candidate),
    };
    if (wanted.isEmpty) return base;

    final match = _trailingPhone.firstMatch(base);
    if (match == null) return base;
    if (!wanted.contains(_digits(match.group(1)!))) return base;
    return _trimSeparators(base.substring(0, match.start));
  }

  /// What gets PERSISTED, and what Wave shows as the CUSTOMER name (owner call
  /// 2026-08-14).
  ///
  /// **A PERSON is named by their phone number** — "(514) 555-1234" — because
  /// the invoicing workflow in Wave identifies people by number. Their actual
  /// name is in `firstName`/`lastName`, which is what [displayFor] renders in
  /// the app, so nothing is lost.
  ///
  /// **A BUSINESS keeps its name**, because that name IS how Wave identifies
  /// it: "3101-5696 qc inc.", "1505 Village de Bergerac". Replacing it with a
  /// number would make the customer unrecognisable on a real invoice, and
  /// unlike a person there is usually no first/last to fall back on.
  /// [looksLikeBusinessName] is what catches the Wave-imported ones, which
  /// carry no [type] at all.
  ///
  /// Both branches are idempotent, which is what lets the backfill and every
  /// ordinary save re-run: a person's number recomposes to itself, and a
  /// business's name is returned stripped and unchanged.
  ///
  /// [baseName] is also the answer for a person with no number at all — a Wave
  /// customer still needs something to be called, and a blank would float the
  /// doc to the top of the name-ordered client list with no initial for its
  /// avatar.
  static String composeStored({
    required String baseName,
    required String phone,
    String mobile = '',
    ClientType type = ClientType.unset,
    String businessName = '',
  }) {
    final base = stripPhone(baseName, phone: phone, mobile: mobile);
    if (isBusiness(type: type, businessName: businessName) ||
        looksLikeBusinessName(base)) {
      return base;
    }

    final number = phone.trim().isNotEmpty ? phone.trim() : mobile.trim();
    return number.isNotEmpty ? number : base;
  }

  /// Company-name tokens, bounded by non-letters so "Inc." is a business and
  /// "Vincent" is not. Matched against an accent-folded, lowercased name, so
  /// "Ltée" arrives here as "ltee" — a `\b` after "é" would never fire, since
  /// Dart's word boundary is ASCII-only.
  ///
  /// Deliberately short. A false positive only leaves a client named the way
  /// it already was; a false NEGATIVE renames a real customer to a phone
  /// number on live Wave invoices.
  static final _businessToken = RegExp(
    '(^|[^a-z])(inc|ltd|ltee|llc|llp|enr|senc|sencrl|cie|corp|corporation|'
    'company|holdings|group|groupe|services|solutions|technology|'
    'technologies|entreprise|entreprises|immobilier|immeuble|immeubles|'
    'gestion|construction|condo|condos|syndicat|copropriete|residence|'
    r'residences|habitations|logements|appartements)([^a-z]|$)',
  );

  /// ANY digit left in the name once the client's own number is off it —
  /// "1505 Village de Bergerac", "3101-5696 qc inc.", "Condo 706".
  ///
  /// Deliberately blunt, and biased on purpose. A person's name does not
  /// contain digits, so the only false positives are a person carrying a
  /// SECOND, older number in their name — and the cost of that is merely that
  /// they keep the name they already had, which the backfill reports. The
  /// opposite mistake renames a real company on live Wave invoices.
  static final _anyDigit = RegExp(r'\d');

  /// Whether [name] reads as an ORGANIZATION on its face.
  ///
  /// This is the fallback for the docs that carry no `type`: the Wave import
  /// sets none, so every imported business would otherwise read as a person
  /// and be renamed to its phone number. It is a heuristic and it is meant to
  /// be — the backfill lists everything it matches, and everything it renames,
  /// so the call can be checked before a single Wave customer is touched.
  static bool looksLikeBusinessName(String name) {
    final value = name.trim();
    if (value.isEmpty) return false;
    if (_anyDigit.hasMatch(value)) return true;
    final folded = value
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e');
    return _businessToken.hasMatch(folded);
  }

  /// The clean name to hand back to [composeStored] when RE-SAVING a stored
  /// client — the stored [name] with its number stripped, never [displayFor].
  ///
  /// The distinction is the whole point, and getting it wrong renames real
  /// Wave customers. `clients/{id}.name` IS Wave's customer name, and on a
  /// business it holds the BUSINESS while `firstName`/`lastName` hold its
  /// contact person. [displayFor] prefers those halves for anything it reads
  /// as a person — including every Wave-imported doc, since the import sets no
  /// `type` — so seeding an edit form from the display name and saving it back
  /// replaces "Vogas Plumbing" with "Marc Tremblay" on live invoices.
  ///
  /// Hand-mirrors `baseNameFor` in
  /// `functions/scripts/backfill-client-name-with-phone.js`, including the
  /// fallback order: the first/last halves are reached only when the stored
  /// name is empty once its own number is stripped, which is the junk case.
  static String baseNameFor({
    required String name,
    String phone = '',
    String mobile = '',
    String firstName = '',
    String lastName = '',
    String businessName = '',
  }) {
    final stored = stripPhone(name, phone: phone, mobile: mobile);
    if (stored.isNotEmpty) return stored;

    final composed = [
      firstName.trim(),
      lastName.trim(),
    ].where((half) => half.isNotEmpty).join(' ');
    if (composed.isNotEmpty) return composed;

    return stripPhone(businessName, phone: phone, mobile: mobile);
  }

  /// Whether this client is an ORGANIZATION rather than a person — which
  /// decides whose name identifies it in [displayFor].
  ///
  /// `propertyManagement` counts: a property-management company is a business
  /// with a contact person, exactly the shape [displayFor] has to get right.
  ///
  /// The legacy `businessName` clause is the second half, and it is not
  /// belt-and-braces: pre-Wave-reshape business docs predate the `type` field
  /// entirely, so they are `unset` and would otherwise be read as people. That
  /// field is only ever populated on a business.
  static bool isBusiness({
    ClientType type = ClientType.unset,
    String businessName = '',
  }) =>
      type == ClientType.commercial ||
      type == ClientType.propertyManagement ||
      businessName.trim().isNotEmpty;

  /// What every in-app surface shows.
  ///
  /// **A BUSINESS shows its business name; a person shows their first/last
  /// halves** (owner call 2026-08-14). The two branches exist because
  /// `firstName`/`lastName` mean different things on the two kinds of client:
  /// on a person they ARE the client, and on a business they are only its
  /// contact person — so preferring them everywhere would render "Vogas
  /// Plumbing" as "Marc Tremblay" on the card for a commercial job.
  ///
  /// For a person the halves win over the stored [name] because [name] is
  /// Wave's field: it carries the phone number, and on an imported customer it
  /// is whatever Wave had.
  ///
  /// Every branch ends at the same three fallbacks, just in a different order,
  /// so a client missing the field its own branch prefers still renders
  /// something. The last resort is the raw [name] — a bare number beats an
  /// empty string, which would float the doc to the top of the name-ordered
  /// list with no initial for its avatar.
  static String displayFor({
    required String name,
    String phone = '',
    String mobile = '',
    String firstName = '',
    String lastName = '',
    String businessName = '',
    ClientType type = ClientType.unset,
  }) {
    final base = stripPhone(name, phone: phone, mobile: mobile);
    final business = stripPhone(businessName, phone: phone, mobile: mobile);
    final composed = [
      firstName.trim(),
      lastName.trim(),
    ].where((half) => half.isNotEmpty).join(' ');

    if (isBusiness(type: type, businessName: businessName)) {
      // `name` first: that is where the business itself lives, and the legacy
      // `businessName` is only reached on a doc whose `name` is blank or was
      // nothing but a phone number.
      if (base.isNotEmpty) return base;
      if (business.isNotEmpty) return business;
      // No company name on file at all — the contact person is better than
      // rendering the phone number.
      if (composed.isNotEmpty) return composed;
      return name.trim();
    }

    if (composed.isNotEmpty) return composed;
    if (base.isNotEmpty) return base;
    if (business.isNotEmpty) return business;
    return name.trim();
  }

  /// The first dialable 10-digit number in [text], formatted `(514) 555-1234`,
  /// or null when there isn't a clean one.
  ///
  /// Deliberately NARROWER than [formatPhoneNumber], which passes an
  /// international `+` number through untouched and appends digits past the
  /// tenth verbatim. Those are ambiguities the app tolerates from an admin
  /// typing into the phone FIELD; pulling a number out of free text must not
  /// guess at them. The exactly-10 threshold is also what stops this matching
  /// a street number, a postal code or a year.
  static String? extractPhone(String text) => _matchPhone(text)?.formatted;

  /// Moves a phone number the admin typed or pasted into the NAME field over
  /// into the phone field, and takes it back out of the name.
  ///
  /// Returns null when there is nothing to do — which is the common case, so
  /// callers can use it as their "did anything change" test.
  ///
  /// Two rules carried over from the one-off backfill this replaces:
  /// a typed phone always WINS (an existing [phone] means the name's number is
  /// a duplicate or a second line, and guessing between them is worse than
  /// leaving it), and a name that is NOTHING but the number keeps it — the
  /// name is required, so emptying the field would look like the paste
  /// vanished.
  static ({String name, String phone})? liftPhoneFromName({
    required String name,
    required String phone,
  }) {
    if (phone.trim().isNotEmpty) return null;
    final match = _matchPhone(name);
    if (match == null) return null;

    final remaining = _trimSeparators(
      '${name.substring(0, match.start)} ${name.substring(match.end)}',
    );
    if (remaining.isEmpty) return (name: name, phone: match.formatted);
    return (name: remaining, phone: match.formatted);
  }

  static ({int start, int end, String formatted})? _matchPhone(String text) {
    for (final match in _candidate.allMatches(text)) {
      final candidate = match.group(0)!;
      // An international number has no fixed shape, so bracketing its first
      // three digits as an area code would be wrong. Leave it in the name.
      if (candidate.contains('+')) continue;
      if (_digits(candidate).length != 10) continue;
      return (
        start: match.start,
        end: match.end,
        formatted: formatPhoneNumber(_digits(candidate)),
      );
    }
    return null;
  }
}
