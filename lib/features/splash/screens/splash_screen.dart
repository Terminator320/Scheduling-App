import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/splash/application/splash_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  static const Duration displayDuration = Duration(seconds: 3);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  final ValueNotifier<bool> _show = ValueNotifier(false);

  Widget? _destination;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show.value = true);
    _init();
  }

  @override
  void dispose() {
    _show.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    Widget destination = const Login();

    final resolution = ref
        .read(splashDestinationProvider.future)
        .then<void>((d) {
          destination = switch (d) {
            SplashGoToLogin() => const Login(),
            SplashGoToCalendar(:final isAdmin, :final employeeId) =>
              MainCalendar(isAdmin: isAdmin, employeeId: employeeId),
          };
        })
        .catchError((Object e, StackTrace st) {
          ref.read(loggerProvider).warn('splash resolution failed', e, st);
        });

    await Future.wait<void>([
      Future<void>.delayed(SplashScreen.displayDuration),
      resolution,
    ]);

    if (!mounted) return;
    setState(() {
      _destination = destination;
      _navigating = true;
    });
    _show.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageTransitionSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
        animation: primary,
        secondaryAnimation: secondary,
        child: child,
      ),
      child: _navigating && _destination != null
          ? _destination!
          : Scaffold(
              key: const ValueKey('splash'),
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary,
                      scheme.primary.withValues(alpha: 0.85),
                      scheme.primary.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _show,
                    builder: (context, show, child) => Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _Stagger(
                                  show: show,
                                  delay: Duration.zero,
                                  child: Image.asset(
                                    'assets/images/logo1.png',
                                    height: 120,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _Stagger(
                                  show: show,
                                  delay: const Duration(milliseconds: 120),
                                  child: Text(
                                    context.l10n.schedulingApp,
                                    style: GoogleFonts.inter(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onPrimary,
                                      letterSpacing: -0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _Stagger(
                                  show: show,
                                  delay: const Duration(milliseconds: 200),
                                  child: Text(
                                    context.l10n.hopeYouAreEnjoyingYourDay,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onPrimary.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _Stagger(
                          show: show,
                          delay: const Duration(milliseconds: 280),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: 48,
                              left: 48,
                              right: 48,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                backgroundColor: scheme.onPrimary.withValues(
                                  alpha: 0.2,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  scheme.onPrimary,
                                ),
                                minHeight: 3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _Stagger extends StatefulWidget {
  const _Stagger({
    required this.show,
    required this.delay,
    required this.child,
  });

  final bool show;
  final Duration delay;
  final Widget child;

  @override
  State<_Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<_Stagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    reverseDuration: const Duration(milliseconds: 250),
  );

  @override
  void didUpdateWidget(_Stagger old) {
    super.didUpdateWidget(old);
    if (widget.show != old.show) _drive();
  }

  @override
  void initState() {
    super.initState();
    if (widget.show) _drive();
  }

  Future<void> _drive() async {
    if (widget.show) {
      await Future<void>.delayed(widget.delay);
      if (mounted) _c.forward();
    } else {
      if (mounted) _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeScaleTransition(animation: _c, child: widget.child);
  }
}
