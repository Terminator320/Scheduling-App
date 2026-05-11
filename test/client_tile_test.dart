// test/client_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/client_tile.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

ClientRecord _fakeClient({String phone = '514-555-0101'}) => ClientRecord(
      id: 'c1',
      name: 'Sarah Johnson',
      address: '123 Main St',
      phone: phone,
      contacts: [],
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows client display name', (tester) async {
    await tester.pumpWidget(_wrap(ClientTile(client: _fakeClient())));
    expect(find.textContaining('Sarah'), findsOneWidget);
  });

  testWidgets('shows phone number', (tester) async {
    await tester.pumpWidget(_wrap(ClientTile(client: _fakeClient())));
    expect(find.text('514-555-0101'), findsOneWidget);
  });

  testWidgets('shows AppAvatar', (tester) async {
    await tester.pumpWidget(_wrap(ClientTile(client: _fakeClient())));
    expect(find.byType(AppAvatar), findsOneWidget);
  });

  testWidgets('calls onOpen when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(
      ClientTile(client: _fakeClient(), onOpen: () async => tapped = true),
    ));
    await tester.tap(find.byType(ClientTile));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('does not overflow at small screen + 2x text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(260 * 3, 200 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: _wrap(ClientTile(client: _fakeClient())),
    ));
    expect(tester.takeException(), isNull);
  });
}
