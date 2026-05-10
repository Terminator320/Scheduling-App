import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/core/notices/notice_service.dart';

/// Wires an `AsyncValue`-bearing provider to the `NoticeService` so that any
/// failure state surfaces as an error SnackBar. Screens opt in by listing
/// the providers they care about — there is no global observer that could
/// surface errors from unrelated screens.
///
/// Usage:
///
/// ```dart
/// AppErrorListener(
///   providers: [clientsControllerProvider],
///   child: ClientsScaffold(...),
/// )
/// ```
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
    // Avoid pulling in feature-level l10n keys here; the fallback string is
    // intentionally generic. Per-feature failures override this via their
    // own `toLocalizedMessage`.
    return const UnknownFailure(
      cause: 'unknown',
      stackTrace: StackTrace.empty,
    ).toLocalizedMessage(context);
  }
}
