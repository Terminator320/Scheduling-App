import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/splash/application/splash_controller.dart';
import 'package:scheduling/routes/app_routes.dart';

/// Auth-gate splash. Visually matches the OS native splash
/// (`flutter_native_splash`) so the handoff is seamless: same logo, same
/// brand-color background. A linear progress indicator at the bottom
/// signals work while the destination resolves.
///
/// Returning users take an optimistic fast path: if [AuthCache] holds an
/// identity for the signed-in uid, we route straight to the calendar as a
/// (least-privilege) employee without waiting on a Firestore read. The live
/// role stream then upgrades real admins (`MainCalendar`), and the account
/// listeners in `main.dart` sign out a disabled or deleted account — so the
/// authoritative [splashDestinationProvider] only runs on a cache miss.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _splashRemoved = false;
  bool _navigated = false;
  bool _useAuthoritative = false;

  @override
  void initState() {
    super.initState();
    // Register once — not in build(), which would schedule a new callback on
    // every rebuild (ref.listen + the progress animation rebuild this widget).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _removeNativeSplashOnce(),
    );
    _decideRoute();
  }

  /// Optimistic fast path. On a cache hit we route immediately (as employee);
  /// on a miss we fall back to the authoritative [splashDestinationProvider].
  Future<void> _decideRoute() async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) {
      _go(const SplashGoToLogin());
      return;
    }
    EmployeeRecord? cached;
    try {
      cached = await AuthCache().loadIfMatch(uid);
    } catch (e, st) {
      ref.read(loggerProvider).warn('splash.auth_cache_load', e, st);
      cached = null;
    }
    if (!mounted || _navigated) return;
    if (cached != null) {
      _go(SplashGoToCalendar(isAdmin: false, employeeId: cached.id));
      return;
    }
    setState(() => _useAuthoritative = true);
  }

  void _removeNativeSplashOnce() {
    if (_splashRemoved) return;
    _splashRemoved = true;
    FlutterNativeSplash.remove();
  }

  void _go(SplashDestination destination) {
    if (_navigated || !mounted) return;
    _navigated = true;
    final nav = Navigator.of(context);
    switch (destination) {
      case SplashGoToLogin():
        nav.pushReplacementNamed(AppRoutes.login);
      case SplashGoToCalendar(:final isAdmin, :final employeeId):
        nav.pushReplacementNamed(
          AppRoutes.mainCalendar,
          arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only consult the authoritative read on a cache miss. Watching it on the
    // optimistic path would run its sign-out side effects underneath us.
    if (_useAuthoritative) {
      ref.listen<AsyncValue<SplashDestination>>(splashDestinationProvider, (
        _,
        next,
      ) {
        next.when(
          data: _go,
          error: (e, st) {
            ref.read(loggerProvider).warn('splash resolution failed', e, st);
            _go(const SplashGoToLogin());
          },
          loading: () {},
        );
      });

      ref.read(splashDestinationProvider).whenData(_go);
    }

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.primary,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Image.asset(
                  'assets/images/logo_splash.png',
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 48, left: 48, right: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  backgroundColor: scheme.onPrimary.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
