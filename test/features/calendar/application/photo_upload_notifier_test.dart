import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';

void main() {
  late PhotoUploadNotifier notifier;

  setUp(() => notifier = PhotoUploadNotifier());
  tearDown(() => notifier.dispose());

  test('reportFailure is a no-op when there is nothing to report', () {
    notifier.reportFailure('a1');

    expect(notifier.failureFor('a1'), isNull);
    expect(notifier.latestFailure.value, isNull);
  });

  test('reportFailure records a failure and publishes it as the latest', () {
    notifier.reportFailure('a1', failedCount: 2);

    final failure = notifier.failureFor('a1');
    expect(failure, isNotNull);
    expect(failure!.failedCount, 2);
    expect(notifier.latestFailure.value, same(failure));
  });

  test('reportFailure stores an unmodifiable tooLargeFileNames list', () {
    notifier.reportFailure('a1', tooLargeFileNames: ['big.jpg']);

    final failure = notifier.failureFor('a1')!;
    expect(failure.tooLargeFileNames, ['big.jpg']);
    expect(() => failure.tooLargeFileNames.add('x'), throwsUnsupportedError);
  });

  test('clearFailure removes the stored failure', () {
    notifier
      ..reportFailure('a1', failedCount: 1)
      ..clearFailure('a1');

    expect(notifier.failureFor('a1'), isNull);
  });
}
