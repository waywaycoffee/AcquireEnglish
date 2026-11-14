import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';

/// Karaoke (current-word) styles.
///
/// Product default matches ShadowTalk: green text, no yellow/blue chips.
/// Legacy setting values like `黄色填充` are remapped so old installs stop
/// painting yellow blocks on every active word.
class SubtitleWordHighlightStyle {
  const SubtitleWordHighlightStyle._();

  /// Normalize persisted styles onto the sparse green-text look.
  static String effectiveStyle(String style) {
    switch (style) {
      case '下划线':
        return '下划线';
      case '描边':
        return '描边';
      case '蓝色填充':
      case '黄色填充':
      case '绿色填充':
      default:
        return '绿色填充';
    }
  }

  static Color background(String style, {required bool highlighted}) {
    if (!highlighted) {
      return Colors.transparent;
    }
    switch (effectiveStyle(style)) {
      case '描边':
        return const Color(0xFFF1F5F9);
      case '下划线':
      case '绿色填充':
      default:
        return Colors.transparent;
    }
  }

  static Color borderColor(String style, {required bool highlighted}) {
    if (!highlighted) {
      return Colors.transparent;
    }
    switch (effectiveStyle(style)) {
      case '描边':
        return const Color(0xFF64748B);
      case '下划线':
      case '绿色填充':
      default:
        return Colors.transparent;
    }
  }

  static Color textColor(
    String style, {
    required bool highlighted,
    required Color fallback,
  }) {
    if (!highlighted) {
      return fallback;
    }
    switch (effectiveStyle(style)) {
      case '描边':
        return fallback;
      case '下划线':
      case '绿色填充':
      default:
        return AppDesignTokens.brandGreen;
    }
  }

  static double borderWidth(
    String style, {
    required bool highlighted,
    required double width,
  }) {
    if (!highlighted) {
      return 0;
    }
    if (effectiveStyle(style) == '描边') {
      return width;
    }
    return 0;
  }

  static TextDecoration? textDecoration(
    String style, {
    required bool highlighted,
  }) {
    return highlighted && effectiveStyle(style) == '下划线'
        ? TextDecoration.underline
        : null;
  }

  static Color? textDecorationColor(String style, {required bool highlighted}) {
    return highlighted && effectiveStyle(style) == '下划线'
        ? AppDesignTokens.brandGreen
        : null;
  }
}
