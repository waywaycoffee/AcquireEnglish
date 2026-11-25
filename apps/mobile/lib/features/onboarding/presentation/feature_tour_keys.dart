import 'package:flutter/material.dart';

import '../../navigation/presentation/floating_bottom_nav.dart';

/// Shared [GlobalKey]s so the coach overlay can measure real widgets.
class FeatureTourKeys {
  FeatureTourKeys._();

  static final GlobalKey recentWatched = GlobalKey(
    debugLabel: 'feature_tour_recent_watched',
  );

  static final GlobalKey navLibrary = GlobalKey(
    debugLabel: 'feature_tour_nav_library',
  );

  static final GlobalKey navReading = GlobalKey(
    debugLabel: 'feature_tour_nav_reading',
  );

  static final GlobalKey navOral = GlobalKey(
    debugLabel: 'feature_tour_nav_oral',
  );

  static final GlobalKey navMore = GlobalKey(
    debugLabel: 'feature_tour_nav_more',
  );

  static final GlobalKey<FloatingBottomNavState> bottomNav =
      GlobalKey<FloatingBottomNavState>(
    debugLabel: 'feature_tour_bottom_nav',
  );
}
