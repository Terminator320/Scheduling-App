import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

/// First-launch intro carousel. Swipeable slides with a page-dot indicator;
/// "Get Started"/"Skip" hand control back to the caller via [onFinish].
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onFinish, super.key});

  /// Marks onboarding complete and advances to the auth/splash flow.
  final Future<void> Function() onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Onboarding is the first visible screen on a fresh install, so it owns
    // the handoff from the OS native splash.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FlutterNativeSplash.remove(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _advance(int count) {
    if (_index >= count - 1) {
      widget.onFinish();
      return;
    }
    _controller.nextPage(duration: AppDuration.fast, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slides = <_OnboardingSlide>[
      _OnboardingSlide(
        icon: FontAwesomeIcons.calendarCheck,
        title: context.l10n.onboarding_slide1Title,
        body: context.l10n.onboarding_slide1Body,
      ),
      _OnboardingSlide(
        icon: FontAwesomeIcons.userGroup,
        title: context.l10n.onboarding_slide2Title,
        body: context.l10n.onboarding_slide2Body,
      ),
      _OnboardingSlide(
        icon: FontAwesomeIcons.screwdriverWrench,
        title: context.l10n.onboarding_slide3Title,
        body: context.l10n.onboarding_slide3Body,
      ),
    ];
    final isLast = _index == slides.length - 1;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onFinish,
                child: Text(context.l10n.onboarding_skip),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: slides.length,
                itemBuilder: (context, index) =>
                    _SlideView(slide: slides[index]),
              ),
            ),
            SmoothPageIndicator(
              controller: _controller,
              count: slides.length,
              effect: ExpandingDotsEffect(
                dotHeight: 8,
                dotWidth: 8,
                activeDotColor: scheme.primary,
                dotColor: scheme.outlineVariant,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sp24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _advance(slides.length),
                  child: Text(
                    isLast
                        ? context.l10n.onboarding_getStarted
                        : context.l10n.onboarding_next,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
  });

  // FontAwesome icons are FaIconData (a distinct type from IconData in v11).
  final FaIconData icon;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.r16),
            ),
            alignment: Alignment.center,
            child: FaIcon(slide.icon, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: AppSpacing.sp24),
          Text(
            slide.title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sp12),
          Text(
            slide.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
