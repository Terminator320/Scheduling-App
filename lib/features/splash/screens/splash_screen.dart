import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/splash/application/splash_controller.dart';
import 'package:scheduling/routes/app_routes.dart';

/// Auth-gate splash. Visually matches the OS native splash
/// (`flutter_native_splash`) so the handoff is seamless: same logo, same
/// brand-color background. A linear progress indicator at the bottom
/// signals work while [splashDestinationProvider] resolves. Once resolved,
/// the native splash is removed and the route is replaced with Login or
/// MainCalendar.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _splashRemoved = false;
  bool _navigated = false;

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _removeNativeSplashOnce(),
    );

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
