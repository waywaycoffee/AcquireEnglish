import 'package:flutter/material.dart';

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

  /// Host key for the primary nav chrome (icon rail).
  static final GlobalKey bottomNav = GlobalKey(
    debugLabel: 'feature_tour_nav_rail',
  );
}
