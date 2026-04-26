import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const Duration displayDuration = Duration(seconds: 3);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _fadeOut;

  @override
  void initState() {
    super.initState();

    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Exit shorter than enter (~60% — feels responsive on hand-off).
    _fadeOut = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1.0,
    );

    _enter.forward();
    _init();
  }

  @override
  void dispose() {
    _enter.dispose();
    _fadeOut.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    Widget? destination;

    await Future.wait([
      Future.delayed(SplashScreen.displayDuration),
      _resolveAuth().then((d) => destination = d),
    ]);

    if (!mounted) return;

    await _fadeOut.reverse();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => destination!,
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: child,
        ),
      ),
    );
  }

  Future<Widget> _resolveAuth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Login();

    final userDoc = await UserService().findUserByUid(user.uid);
    if (userDoc == null) {
      await FirebaseAuth.instance.signOut();
      return const Login();
    }

    final employee = EmployeeRecord.fromMap(userDoc.id, userDoc.data());
    return MainCalendar(isAdmin: employee.isAdmin, employeeId: employee.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return FadeTransition(
      opacity: _fadeOut,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SplashItem(
                  controller: _enter,
                  start: 0.0,
                  end: 0.55,
                  reduceMotion: reduceMotion,
                  builder: (t) => Transform.scale(
                    // Spring-like overshoot via easeOutBack (t can exceed 1.0).
                    scale: reduceMotion ? 1.0 : 0.85 + 0.15 * t,
                    child: Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Image.asset('assets/images/logo1.png', height: 170),
                    ),
                  ),
                  curve: Curves.easeOutBack,
                ),
                const SizedBox(height: 32),
                _SplashItem(
                  controller: _enter,
                  start: 0.20,
                  end: 0.75,
                  reduceMotion: reduceMotion,
                  builder: (t) => Transform.translate(
                    offset: Offset(0, (1 - t) * 12),
                    child: Opacity(
                      opacity: t,
                      child: Text(
                        'Welcome to Scheduling App',
                        style: textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SplashItem(
                  controller: _enter,
                  start: 0.32,
                  end: 0.85,
                  reduceMotion: reduceMotion,
                  builder: (t) => Transform.translate(
                    offset: Offset(0, (1 - t) * 12),
                    child: Opacity(
                      opacity: t,
                      child: Text(
                        'Hope you are enjoying your day!',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withAlpha(150),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _SplashItem(
                  controller: _enter,
                  start: 0.45,
                  end: 1.0,
                  reduceMotion: reduceMotion,
                  builder: (t) => Opacity(
                    opacity: t,
                    child: CircularProgressIndicator(color: scheme.secondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Drives a staggered entrance for one element using a slice of the parent
// controller's [0..1] timeline.
class _SplashItem extends StatelessWidget {
  const _SplashItem({
    required this.controller,
    required this.start,
    required this.end,
    required this.builder,
    required this.reduceMotion,
    this.curve = Curves.easeOutCubic,
  });

  final AnimationController controller;
  final double start;
  final double end;
  final Curve curve;
  final bool reduceMotion;
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return builder(1.0);
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: curve),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => builder(anim.value),
    );
  }
}
