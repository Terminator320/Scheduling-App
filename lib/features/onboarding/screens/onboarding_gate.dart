import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';
import 'package:scheduling/features/onboarding/screens/onboarding_screen.dart';
import 'package:scheduling/features/splash/screens/splash_screen.dart';

/// App entry gate: shows the onboarding flow once on first launch, then hands
/// off to the auth splash. The seen-flag lives in encrypted storage. While it
/// loads, the OS native splash is still on screen, so a brand-colored surface
/// behind it suffices.
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key});

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  bool? _seen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seen = await ref
        .read(secureStorageServiceProvider)
        .readFlag(SecureStorageKeys.onboardingSeen);
    if (mounted) setState(() => _seen = seen);
  }

  Future<void> _finish() async {
    await ref
        .read(secureStorageServiceProvider)
        .writeFlag(SecureStorageKeys.onboardingSeen, value: true);
    if (mounted) setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) {
      return ColoredBox(color: Theme.of(context).colorScheme.primary);
    }
    if (seen) return const SplashScreen();
    return OnboardingScreen(onFinish: _finish);
  }
}
