import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Bottom clearance so chrome stays above Android's system navigation /
/// gesture bar when the app runs edge-to-edge.
double systemBottomInsetOf(BuildContext context) {
  final MediaQueryData media = MediaQuery.of(context);
  return math.max(media.viewPadding.bottom, media.padding.bottom);
}
