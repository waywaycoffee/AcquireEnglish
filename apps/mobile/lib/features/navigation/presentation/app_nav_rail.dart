import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/presentation/feature_tour_keys.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'navigation_destination.dart';

/// Phone / narrow shell: vertical icon rail (no bottom tabs).
///
/// Wide layouts keep [PadSidebar]; this rail is the phone form-factor
/// counterpart aligned with feature-entry-map primary entries.
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    required this.current,
    super.key,
    this.attachTourKeys = false,
  });

  final AppNavDestination current;
  final bool attachTourKeys;

  static const double width = 64;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final List<AppNavDestination> primary =
        AppNavDestination.sidebarRailDestinations;
    final Color accent = AppDesignTokens.navAccent;
    final Color accentSoft = AppDesignTokens.navAccentSoft;

    return Material(
      color: AppDesignTokens.appWhite,
      child: SizedBox(
        width: width,
        child: Column(
          children: <Widget>[
            SizedBox(height: topInset + 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/img/app_icon.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
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
                    accentSoft: accentSoft,
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
              accentSoft: accentSoft,
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
    // Word-book subroutes still highlight 课程.
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
    required this.accentSoft,
    required this.onTap,
    super.key,
  });

  final AppNavDestination destination;
  final bool selected;
  final Color accent;
  final Color accentSoft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: destination.label,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected ? accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  selected ? destination.activeIcon : destination.icon,
                  size: 22,
                  color: selected ? accent : AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? accent : AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
