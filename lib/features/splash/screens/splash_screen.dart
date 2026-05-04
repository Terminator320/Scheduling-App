import 'package:animations/animations.dart';
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

class _SplashScreenState extends State<SplashScreen> {
  // Drives FadeScaleTransition for each splash element. Flipped from 0→1 on
  // first frame; flipped back to 0 just before navigating away.
  final ValueNotifier<bool> _show = ValueNotifier(false);

  Widget? _destination;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    // Defer to the next frame so the first build completes before animations start.
    WidgetsBinding.instance.addPostFrameCallback((_) => _show.value = true);
    _init();
  }

  @override
  void dispose() {
    _show.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    Widget? destination;

    // Run auth resolution and the minimum display time in parallel; whichever
    // finishes last unblocks navigation.
    await Future.wait([
      Future.delayed(SplashScreen.displayDuration),
      _resolveAuth().then((d) => destination = d),
    ]);

    if (!mounted) return;
    setState(() {
      _destination = destination;
      _navigating = true;
    });
    _show.value = false;
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

    // PageTransitionSwitcher gives a Material fade-through (z-axis) when we
    // swap the splash content out for the destination screen.
    return PageTransitionSwitcher(
      duration: const Duration(milliseconds: 400),
      reverse: false,
      transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
        animation: primary,
        secondaryAnimation: secondary,
        child: child,
      ),
      child: _navigating && _destination != null
          ? _destination!
          : Scaffold(
              key: const ValueKey('splash'),
              backgroundColor: theme.scaffoldBackgroundColor,
              body: SafeArea(
                child: Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _show,
                    builder: (_, show, __) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Stagger(
                          show: show,
                          delay: const Duration(milliseconds: 0),
                          child: Image.asset(
                            'assets/images/logo1.png',
                            height: 170,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _Stagger(
                          show: show,
                          delay: const Duration(milliseconds: 120),
                          child: Text(
                            'Welcome to Scheduling App',
                            style: textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _Stagger(
                          show: show,
                          delay: const Duration(milliseconds: 200),
                          child: Text(
                            'Hope you are enjoying your day!',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface.withAlpha(150),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _Stagger(
                          show: show,
                          delay: const Duration(milliseconds: 280),
                          child: CircularProgressIndicator(
                            color: scheme.secondary,
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

// Wraps a child in FadeScaleTransition (Material "appears in place" motion)
// driven by an AnimationController, with a per-item start delay for stagger.
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
      await Future.delayed(widget.delay);
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
