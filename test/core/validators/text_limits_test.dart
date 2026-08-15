import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/validators/text_limits.dart';

/// S2: `TextLimits` caps must be applied through
/// `LengthLimitingTextInputFormatter`, which truncates a too-long paste
/// rather than rejecting it outright.
void main() {
  test('LengthLimitingTextInputFormatter truncates to cap', () {
    final formatter = LengthLimitingTextInputFormatter(
      TextLimits.appointmentTitle,
    );
    final tooLong = 'x' * (TextLimits.appointmentTitle + 50);

    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: tooLong,
        selection: TextSelection.collapsed(offset: tooLong.length),
      ),
    );

    expect(result.text.length, TextLimits.appointmentTitle);
  });

  test('caps stay within Firestore safe ranges', () {
    // Guards against a cap being bumped into the megabyte range, which
    // would blow past Firestore's 1 MiB doc-size ceiling.
    expect(TextLimits.appointmentTitle, lessThan(10000));
    expect(TextLimits.appointmentAddress, lessThan(10000));
    expect(TextLimits.appointmentNotes, lessThan(50000));
    expect(TextLimits.appointmentMaterials, lessThan(50000));
    expect(TextLimits.personName, lessThan(10000));
    expect(TextLimits.phone, lessThan(100));
    expect(TextLimits.email, lessThan(1000));
  });

  group('client caps never exceed the firestore.rules caps', () {
    // Dart, CEL and JS cannot share a constant, so these caps are a
    // hand-mirror — and this repo has been bitten in BOTH directions: a
    // client cap above the rules cap makes every long value fail the write
    // with an opaque `permission-denied`, and a rules cap below the widest
    // value a shipped write path can produce makes those docs permanently
    // un-updatable. Reading the rules text back is the only mechanism
    // available to turn that comment into a failing build.
    late final rules = File('firestore.rules').readAsStringSync();

    /// The TIGHTEST cap firestore.rules puts on `field`, across both forms the
    /// rules use: the `isBoundedString(d.x, N)` helper and the inline
    /// `data.x.size() <= N` the client-data validator is written with.
    ///
    /// The minimum, not the first match: several names appear in more than one
    /// collection's validator (`phone` is 40 on `/users` but 32 on `/clients`),
    /// and a client cap has to clear whichever rule can reject the write.
    int rulesCapFor(String field) {
      final name = RegExp.escape(field);
      final caps = [
        ...RegExp(
          r'isBoundedString\(\s*(?:d|data|request\.resource\.data)\.' +
              name +
              r'\s*,\s*(\d+)\s*\)',
        ).allMatches(rules),
        ...RegExp(
          r'(?:d|data|request\.resource\.data)\.' +
              name +
              r'\.size\(\)\s*<=\s*(\d+)',
        ).allMatches(rules),
      ].map((m) => int.parse(m.group(1)!)).toList();
      expect(
        caps,
        isNotEmpty,
        reason: 'no length cap found for "$field" in firestore.rules',
      );
      return caps.reduce((a, b) => a < b ? a : b);
    }

    // Appointment fields — all four are currently exactly equal, so a bump on
    // either side breaks the write. That is the point of pinning them.
    test('appointment title', () {
      expect(
        TextLimits.appointmentTitle,
        lessThanOrEqualTo(rulesCapFor('title')),
      );
    });

    test('appointment address', () {
      expect(
        TextLimits.appointmentAddress,
        lessThanOrEqualTo(rulesCapFor('address')),
      );
    });

    test('appointment notes', () {
      expect(
        TextLimits.appointmentNotes,
        lessThanOrEqualTo(rulesCapFor('notes')),
      );
    });

    test('appointment materials', () {
      expect(
        TextLimits.appointmentMaterials,
        lessThanOrEqualTo(rulesCapFor('materialsNeeded')),
      );
    });

    test('client name, with the phone number appended for Wave', () {
      // The stored `clients/{id}.name` is NOT just what the admin typed — it
      // is `"<typed name> <phone>"`, because that field is synced verbatim as
      // the Wave customer name (ClientNamePolicy.composeStored). So the value
      // the rules have to admit is the sum of the two field caps plus the
      // separating space, and sizing the rule to `personName` alone rejects
      // every long client save with an opaque `permission-denied`.
      expect(
        TextLimits.personName + 1 + TextLimits.phone,
        lessThanOrEqualTo(rulesCapFor('name')),
      );
    });

    test('client email', () {
      expect(TextLimits.email, lessThanOrEqualTo(rulesCapFor('email')));
    });

    test('phone', () {
      expect(TextLimits.phone, lessThanOrEqualTo(rulesCapFor('phone')));
    });

    test('the Wave import truncates below every rules cap', () {
      // The import writes client docs with the Admin SDK, which BYPASSES the
      // rules — so a cap here that exceeds the rules cap does not fail the
      // import, it writes a doc the APP can never update again (every later
      // save is an opaque `permission-denied`). `IMPORT_FIELD_CAPS` is a third
      // hand-mirror of `isValidClientData` and was the only one with nothing
      // pinning it.
      final source = File('functions/wave/mappers.js').readAsStringSync();
      final block = RegExp(
        r'const IMPORT_FIELD_CAPS = \{([^}]*)\}',
      ).firstMatch(source);
      expect(block, isNotNull, reason: 'IMPORT_FIELD_CAPS not found');

      final caps = {
        for (final m in RegExp(
          r'(\w+):\s*(\d+)',
        ).allMatches(block!.group(1)!))
          m.group(1)!: int.parse(m.group(2)!),
      };
      expect(caps, isNotEmpty);

      // `city`/`province`/`country`/`postalCode` are capped inside the rules'
      // address family rather than by their own bare name, so they have no
      // `rulesCapFor` entry to compare against.
      const checked = {
        'name',
        'firstName',
        'lastName',
        'email',
        'phone',
        'mobile',
      };
      for (final entry in caps.entries.where((e) => checked.contains(e.key))) {
        expect(
          entry.value,
          lessThanOrEqualTo(rulesCapFor(entry.key)),
          reason: 'IMPORT_FIELD_CAPS.${entry.key} exceeds its rules cap',
        );
      }
    });
  });

  test('an auth email fits what the account callables accept', () {
    // createEmployeeAccount / changeEmployeeEmail both
    // `requireString(req.data, "email", 254)`. A looser client cap lets the
    // admin type a value the callable rejects as `invalid-argument`, which
    // surfaces as an unexplained "Something went wrong" they cannot fix.
    expect(TextLimits.authEmail, lessThanOrEqualTo(254));

    final source = File(
      'functions/employee_accounts.js',
    ).readAsStringSync();
    final caps = RegExp(
      r'requireString\(\s*req\.data,\s*"email",\s*(\d+)\s*\)',
    ).allMatches(source).map((m) => int.parse(m.group(1)!)).toList();
    expect(caps, isNotEmpty);
    for (final cap in caps) {
      expect(TextLimits.authEmail, lessThanOrEqualTo(cap));
    }
  });
}
