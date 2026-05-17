import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/core/notices/notice_service.dart';

class AppErrorListener extends ConsumerWidget {
  const AppErrorListener({
    required this.child,
    required this.providers,
    super.key,
  });

  final Widget child;
  final List<ProviderListenable<AsyncValue<Object?>>> providers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    for (final provider in providers) {
      ref.listen<AsyncValue<Object?>>(provider, (previous, next) {
        next.whenOrNull(
          error: (error, _) {
            final message = error is Failure
                ? error.toLocalizedMessage(context)
                : _fallback(context);
            ref.read(noticeServiceProvider).error(message);
          },
        );
      });
    }
    return child;
  }

  String _fallback(BuildContext context) {
    return const UnknownFailure(
      cause: 'unknown',
      stackTrace: StackTrace.empty,
    ).toLocalizedMessage(context);
  }
}
