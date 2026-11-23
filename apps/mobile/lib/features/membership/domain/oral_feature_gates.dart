import 'package:flutter/material.dart';

import 'oral_explore_entitlements.dart';

/// Blocks premium oral CTAs that 口语入门探索版 does not include.
/// Custom digital-human selection stays allowed (`features.customDigitalHuman`).
bool oralFeatureAllowed({
  required OralExploreFeatures features,
  required String feature,
}) {
  switch (feature) {
    case 'custom_digital_human':
      return features.customDigitalHuman;
    case 'voice_clone':
      return features.voiceClone;
    case 'hd_export':
      return features.hdExport || features.allowsHdAbove720;
    case 'team_collab':
      return features.teamCollab;
    default:
      return true;
  }
}

void showOralFeatureLockedSnackBar(
  BuildContext context, {
  required String featureLabel,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '「$featureLabel」不在口语入门探索版内，可继续使用基础数字人与自定义形象',
      ),
    ),
  );
}
