// Pins launchExternalUri — the single owner behind launchPhoneCall,
// AddressMapLauncher, EmailComposeLauncher and launchGoogleMapsRoute.
//
// It EXISTS because a hand-rolled copy had lost its try/catch, so a thrown
// launchUrl escaped to the zone handler and was recorded as a FATAL instead of
// a notice. That is the case with no other cover: without a test, deleting the
// catch leaves the whole suite green.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/launchers/external_uri_launcher.dart';
import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';

const _channel = MethodChannel('plugins.flutter.io/url_launcher');
const _uri = 'tel:5145551234';

/// Pumps a widget and hands its context + ref to [body].
Future<void> _run(
  WidgetTester tester,
  Future<void> Function(BuildContext context, WidgetRef ref, NoticeService n)
  body,
) async {
  late BuildContext capturedContext;
  late WidgetRef capturedRef;
  late NoticeService notices;

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            capturedContext = context;
            capturedRef = ref;
            notices = ref.read(noticeServiceProvider);
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await body(capturedContext, capturedRef, notices);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// Makes the plugin answer `launch` with [result], or throw when [error].
  void mockLauncher({bool result = true, Exception? error}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'canLaunch') return true;
          if (call.method != 'launch') return null;
          if (error != null) throw error;
          return result;
        });
  }

  testWidgets('a thrown launchUrl is caught, not rethrown', (tester) async {
    mockLauncher(error: PlatformException(code: 'boom'));

    await _run(tester, (context, ref, notices) async {
      final seen = <AppNotice>[];
      final sub = notices.stream.listen(seen.add);
      addTearDown(sub.cancel);

      final opened = await launchExternalUri(
        context,
        ref,
        Uri.parse(_uri),
        tag: 'LAUNCH-TEL',
        errorMessage: 'could not call',
      );
      await tester.pump();

      // The whole point: a throw becomes `false` plus a notice. Escaping here
      // is what got filed as a FATAL.
      expect(opened, isFalse);
      expect(tester.takeException(), isNull);
      expect(seen.single.message, 'could not call');
    });
  });

  testWidgets('a false result also surfaces the notice', (tester) async {
    mockLauncher(result: false);

    await _run(tester, (context, ref, notices) async {
      final seen = <AppNotice>[];
      final sub = notices.stream.listen(seen.add);
      addTearDown(sub.cancel);

      final opened = await launchExternalUri(
        context,
        ref,
        Uri.parse(_uri),
        tag: 'LAUNCH-TEL',
        errorMessage: 'could not call',
      );
      await tester.pump();

      expect(opened, isFalse);
      expect(seen.single.message, 'could not call');
    });
  });

  testWidgets('a successful launch reports no notice', (tester) async {
    mockLauncher();

    await _run(tester, (context, ref, notices) async {
      final seen = <AppNotice>[];
      final sub = notices.stream.listen(seen.add);
      addTearDown(sub.cancel);

      final opened = await launchExternalUri(
        context,
        ref,
        Uri.parse(_uri),
        tag: 'LAUNCH-TEL',
        errorMessage: 'could not call',
      );
      await tester.pump();

      expect(opened, isTrue);
      expect(seen, isEmpty);
    });
  });

  testWidgets('a late false result after widget disposal does not throw', (
    tester,
  ) async {
    final launchCompleter = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'canLaunch') return true;
          if (call.method != 'launch') return null;
          return launchCompleter.future;
        });

    await _run(tester, (context, ref, notices) async {
      final seen = <AppNotice>[];
      final sub = notices.stream.listen(seen.add);
      addTearDown(sub.cancel);

      final pending = launchExternalUri(
        context,
        ref,
        Uri.parse(_uri),
        tag: 'LAUNCH-TEL',
        errorMessage: 'could not call',
      );

      await tester.pumpWidget(const SizedBox());
      launchCompleter.complete(false);

      final opened = await pending;
      await tester.pump();

      expect(opened, isFalse);
      expect(tester.takeException(), isNull);
      expect(seen, isEmpty);
    });
  });
}
