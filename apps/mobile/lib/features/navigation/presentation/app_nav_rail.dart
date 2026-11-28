import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/presentation/feature_tour_keys.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'navigation_destination.dart';

/// Phone / narrow shell: vertical icon rail (no bottom tabs).
///
/// Visual: Pencil charcoal rail + coral selected pill.
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    required this.current,
    super.key,
    this.attachTourKeys = false,
  });

  final AppNavDestination current;
  final bool attachTourKeys;

  static const double width = 72;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final List<AppNavDestination> primary =
        AppNavDestination.sidebarRailDestinations;
    final Color accent = AppDesignTokens.navAccent;

    return Material(
      color: AppDesignTokens.softWhite,
      child: SizedBox(
        width: width,
        child: Column(
          children: <Widget>[
            SizedBox(height: topInset + 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/img/app_icon.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '爱快',
                    style: TextStyle(
                      color: AppDesignTokens.brandTeal,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: primary.length,
                itemBuilder: (BuildContext context, int index) {
                  final AppNavDestination destination = primary[index];
                  final bool selected = destination == current ||
                      _routeMatches(current, destination);
                  final Key? tourKey = attachTourKeys
                      ? switch (destination) {
                          AppNavDestination.library =>
                            FeatureTourKeys.navLibrary,
                          AppNavDestination.reading =>
                            FeatureTourKeys.navReading,
                          AppNavDestination.oralCoach =>
                            FeatureTourKeys.navOral,
                          _ => null,
                        }
                      : null;
                  return _RailItem(
                    key: tourKey,
                    destination: destination,
                    selected: selected,
                    accent: accent,
                    onTap: () {
                      if (!selected) {
                        context.go(destination.route);
                      }
                    },
                  );
                },
              ),
            ),
            _RailItem(
              destination: AppNavDestination.settings,
              selected: current == AppNavDestination.settings,
              accent: accent,
              onTap: () {
                if (current != AppNavDestination.settings) {
                  context.go(AppNavDestination.settings.route);
                }
              },
            ),
            SizedBox(height: bottomInset + 8),
          ],
        ),
      ),
    );
  }

  static bool _routeMatches(
    AppNavDestination current,
    AppNavDestination item,
  ) {
    if (current == item) return true;
    if (item == AppNavDestination.words &&
        current.route.startsWith('/words')) {
      return true;
    }
    if (item == AppNavDestination.reading &&
        current.route.startsWith('/reading')) {
      return true;
    }
    if (item == AppNavDestination.exam &&
        current.route.startsWith('/exam')) {
      return true;
    }
    return false;
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.accent,
    required this.onTap,
    super.key,
  });

  final AppNavDestination destination;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: destination.label,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Material(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    selected ? destination.activeIcon : destination.icon,
                    size: 22,
                    color: selected
                        ? AppDesignTokens.onAccent
                        : AppDesignTokens.textSecondary,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? AppDesignTokens.onAccent
                          : AppDesignTokens.textSecondary,
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
