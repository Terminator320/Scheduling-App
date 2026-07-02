import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/splash/application/splash_controller.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/branding/brand_logo.dart';

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
    // P10: Crashlytics/App Check activation completes after runApp (main.dart
    // defers it into firebaseReadyProvider). Every Firestore-reading surface
    // is reached through this splash, so awaiting here guarantees no request
    // races App Check token issuance. An activation failure is already
    // recorded by the zone handler — log and proceed rather than wedge
    // startup on it.
    try {
      await ref.read(firebaseReadyProvider.future);
    } catch (e, st) {
      ref.read(loggerProvider).warn('splash.firebase_ready', e, st);
    }
    if (!mounted || _navigated) return;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      switch (destination) {
        case SplashGoToLogin():
          nav.pushReplacementNamed(AppRoutes.login);
        case SplashGoToCalendar(:final isAdmin, :final employeeId):
          nav.pushReplacementNamed(
            AppRoutes.mainCalendar,
            arguments: MainCalendarArgs(
              isAdmin: isAdmin,
              employeeId: employeeId,
            ),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.primary,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: Center(child: _buildHero(theme))),
            Padding(
              padding: const EdgeInsets.only(bottom: 48, left: 48, right: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.rFull),
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

  /// Mascot mark + the company wordmark in white. The mark stays static and
  /// opaque so it lines up with the OS native splash (no fade-back-in pop at
  /// handoff); only the wordmark — rendered as text, since the navy logo image
  /// would be illegible on brand-blue — fades/rises in. Scroll-wrapped so it
  /// can't overflow at large text scale on a short viewport, and the reveal
  /// collapses to instant under reduce-motion.
  Widget _buildHero(ThemeData theme) {
    Widget wordmark = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp24),
      child: Text(
        brandName,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (!MediaQuery.disableAnimationsOf(context)) {
      wordmark = wordmark
          .animate()
          .fadeIn(duration: 450.ms, curve: Curves.easeOut)
          .slideY(
            begin: 0.4,
            end: 0,
            duration: 450.ms,
            curve: AppAnimationCurves.entrance,
          );
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandMark(size: 156, decorative: true),
          const SizedBox(height: AppSpacing.sp24),
          wordmark,
        ],
      ),
    );
  }
}
