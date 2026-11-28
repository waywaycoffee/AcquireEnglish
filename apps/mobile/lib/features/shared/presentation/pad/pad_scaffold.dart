import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../navigation/presentation/app_nav_rail.dart';
import '../../../navigation/presentation/navigation_destination.dart';
import '../../../onboarding/presentation/feature_tour_keys.dart';
import '../../../onboarding/presentation/feature_tour_overlay.dart';
import '../../../onboarding/presentation/feature_tour_provider.dart';
import '../continue_learning_button.dart';
import 'app_design_tokens.dart';
import 'pad_sidebar.dart';

class PadScaffold extends ConsumerWidget {
  const PadScaffold({
    required this.currentDestination,
    required this.body,
    super.key,
    this.topBar,
    this.useBottomTabWhenPortrait = true,
    this.showNavigation = true,
    this.showContinueLearning = true,
    this.backgroundColor,
  });

  final AppNavDestination currentDestination;
  final Widget body;
  final Widget? topBar;

  /// Kept for call-site compatibility; bottom tabs are retired (left rail only).
  final bool useBottomTabWhenPortrait;
  final bool showNavigation;
  final bool showContinueLearning;

  /// Flat canvas override (e.g. library parchment). Skips bubble backdrop.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Size size = MediaQuery.sizeOf(context);
    final bool useIconRail = size.width < 840;
    final Color scaffoldColor = backgroundColor ?? AppDesignTokens.softWhite;
    final FeatureTourState tour = ref.watch(featureTourProvider);
    final Widget content = _PadBackdrop(
      flatColor: backgroundColor,
      child: Column(
        children: <Widget>[
          if (topBar != null) topBar!,
          Expanded(child: body),
        ],
      ),
    );

    final Widget scaffold = Scaffold(
      backgroundColor: scaffoldColor,
      floatingActionButton: showContinueLearning
          ? const ContinueLearningButton()
          : null,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: <Widget>[
            if (showNavigation)
              useIconRail
                  ? AppNavRail(
                      key: tour.active ? FeatureTourKeys.bottomNav : null,
                      current: currentDestination,
                      attachTourKeys: tour.active,
                    )
                  : PadSidebar(current: currentDestination),
            Expanded(child: content),
          ],
        ),
      ),
    );

    if (!tour.active) {
      return scaffold;
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        scaffold,
        const FeatureTourOverlay(),
      ],
    );
  }
}

class _PadBackdrop extends StatelessWidget {
  const _PadBackdrop({required this.child, this.flatColor});

  final Widget child;
  final Color? flatColor;

  @override
  Widget build(BuildContext context) {
    if (flatColor != null) {
      return ColoredBox(color: flatColor!, child: child);
    }
    final bool compact = MediaQuery.sizeOf(context).width < 840;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppDesignTokens.isDark
                ? const Color(0xFF16181E)
                : const Color(0xFFF7F8FB),
            AppDesignTokens.isDark
                ? const Color(0xFF12141A)
                : const Color(0xFFF0F2F6),
            AppDesignTokens.softWhite,
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          if (!compact) ...<Widget>[
            Positioned(
              left: -36,
              top: 88,
              child: _BackdropBubble(
                size: 160,
                color: AppDesignTokens.skyLight.withValues(alpha: 0.72),
              ),
            ),
            Positioned(
              right: 36,
              top: 112,
              child: _BackdropBubble(
                size: 92,
                color: AppDesignTokens.pinkLight.withValues(alpha: 0.6),
              ),
            ),
            Positioned(
              right: -18,
              bottom: 42,
              child: _BackdropBubble(
                size: 144,
                color: AppDesignTokens.purpleLight.withValues(alpha: 0.42),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

class _BackdropBubble extends StatelessWidget {
  const _BackdropBubble({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
