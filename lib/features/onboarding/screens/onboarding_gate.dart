import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
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
    var seen = false;
    try {
      seen = await ref
          .read(secureStorageServiceProvider)
          .readFlag(SecureStorageKeys.onboardingSeen);
    } catch (e, st) {
      // Encrypted-storage reads can throw on Android (keystore/cipher failure
      // after an OS upgrade or backup-restore). Fail safe to "not seen" so the
      // gate shows onboarding instead of hanging on the brand-color surface.
      ref.read(loggerProvider).warn('ONBOARD-GATE read flag failed', e, st);
    }
    if (mounted) setState(() => _seen = seen);
  }

  Future<void> _finish() async {
    try {
      await ref
          .read(secureStorageServiceProvider)
          .writeFlag(SecureStorageKeys.onboardingSeen, value: true);
    } catch (e, st) {
      // Mirror _load's fail-safe: a keystore/cipher failure writing the flag
      // must not make "Done" a dead button. Proceed past onboarding for this
      // session; worst case the flow shows once more on the next launch.
      ref.read(loggerProvider).warn('ONBOARD-GATE write flag failed', e, st);
    }
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
