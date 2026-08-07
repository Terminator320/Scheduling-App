import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';

/// N1 / N2: locks down the notice surface's basic contract, so a future refactor
/// can't silently drop emissions.
void main() {
  test('success() emits a NoticeSuccess with the message', () async {
    final service = NoticeService();
    addTearDown(service.dispose);

    final received = <AppNotice>[];
    final sub = service.stream.listen(received.add);
    addTearDown(sub.cancel);

    service
      ..success('saved')
      ..error('oops')
      ..info('fyi');

    // Broadcast streams deliver on the next event-loop tick.
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(3));
    expect(received[0], isA<NoticeSuccess>());
    expect(received[0].message, 'saved');
    expect(received[1], isA<NoticeError>());
    expect(received[1].message, 'oops');
    expect(received[2], isA<NoticeInfo>());
  });

  test('stream is broadcast: late listeners only see future events', () async {
    final service = NoticeService();
    addTearDown(service.dispose);

    service.success('lost in space');
    await Future<void>.delayed(Duration.zero);

    final received = <AppNotice>[];
    final sub = service.stream.listen(received.add);
    addTearDown(sub.cancel);

    service.success('caught');
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.message, 'caught');
  });
}
