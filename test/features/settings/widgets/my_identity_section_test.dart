import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/settings/widgets/sections/my_identity_section.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _harness(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _section({
  bool isSaving = false,
  String initialPhone = '(514) 555-0000',
  Future<void> Function(MyIdentityEdit edit)? onSave,
  VoidCallback? onChangeEmail,
}) => MyIdentitySection(
  email: 'theo@example.com',
  initialPhone: initialPhone,
  initialEmergencyContact: 'Ana',
  initialEmergencyPhone: '(514) 555-1111',
  isSaving: isSaving,
  onSave: onSave ?? (_) async {},
  onChangeEmail: onChangeEmail,
);

void main() {
  testWidgets('the save bar is hidden while the form is pristine', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_section()));

    expect(find.byKey(const Key('myIdentitySaveBar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the save bar goes away once the stored value catches up', (
    tester,
  ) async {
    // Dirtiness is computed against the STORED values, and only the
    // controllers were listened to — so a save that commits, re-emits the
    // users doc and rebuilds this section with the new `initialPhone` left the
    // bar on screen (with Discard as a visible no-op) until the next
    // keystroke. Re-pumping with the committed value is exactly that rebuild.
    await tester.pumpWidget(_harness(_section()));

    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-9999');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('myIdentitySaveBar')), findsOneWidget);

    await tester.pumpWidget(
      _harness(_section(initialPhone: '(514) 555-9999')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('myIdentitySaveBar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a field reveals the save bar', (tester) async {
    await tester.pumpWidget(_harness(_section()));

    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-9999');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('myIdentitySaveBar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing is written until save is pressed', (tester) async {
    // The whole point of the bar: typing is not a commit.
    var saves = 0;
    await tester.pumpWidget(_harness(_section(onSave: (_) async => saves++)));

    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-9999');
    await tester.pumpAndSettle();
    expect(saves, 0, reason: 'typing must not write');

    await tester.tap(find.byKey(const Key('myIdentitySave')));
    await tester.pumpAndSettle();
    expect(saves, 1);
  });

  testWidgets('save hands back every identity field', (tester) async {
    MyIdentityEdit? captured;
    await tester.pumpWidget(
      _harness(_section(onSave: (edit) async => captured = edit)),
    );

    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-9999');
    await tester.enterText(find.byKey(const Key('myEmergencyContact')), 'Bea');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('myIdentitySave')));
    await tester.pumpAndSettle();

    expect(captured?.phone, '(514) 555-9999');
    expect(captured?.emergencyContact, 'Bea');
    expect(captured?.emergencyPhone, '(514) 555-1111');
  });

  testWidgets('discard restores the stored value and hides the bar', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_section()));

    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-9999');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('myIdentityDiscard')));
    await tester.pumpAndSettle();

    expect(find.text('(514) 555-0000'), findsOneWidget);
    expect(find.byKey(const Key('myIdentitySaveBar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing a change and typing it back reads as pristine', (
    tester,
  ) async {
    // Dirty is recomputed against the stored values, not latched — otherwise
    // the bar would stay up offering to save nothing.
    await tester.pumpWidget(_harness(_section()));

    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-9999');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('myIdentitySaveBar')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-0000');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('myIdentitySaveBar')), findsNothing);
  });

  testWidgets('discard is disabled while a save is in flight', (tester) async {
    await tester.pumpWidget(_harness(_section(isSaving: true)));

    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-9999');
    // pump, not pumpAndSettle: the busy button's spinner never stops animating.
    await tester.pump();

    final discard = tester.widget<TextButton>(
      find.byKey(const Key('myIdentityDiscard')),
    );
    expect(discard.onPressed, isNull);
  });

  testWidgets('the email row is read-only when no handler is given', (
    tester,
  ) async {
    // Phase B supplies the handler. Until then the row must not offer an edit
    // there is no safe write path for.
    await tester.pumpWidget(_harness(_section()));

    expect(find.byKey(const Key('myChangeEmail')), findsNothing);
    expect(find.text('theo@example.com'), findsOneWidget);
  });

  testWidgets('the email row offers a change action when handed one', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_section(onChangeEmail: () {})));

    expect(find.byKey(const Key('myChangeEmail')), findsOneWidget);
  });

  testWidgets('no overflow at 260px and 2x text', (tester) async {
    tester.view.physicalSize = const Size(260, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _section(),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('myPhone')), '(514) 555-9');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
