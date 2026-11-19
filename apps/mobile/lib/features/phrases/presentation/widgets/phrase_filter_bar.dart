import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';

class PhraseFilterBar extends StatelessWidget {
  const PhraseFilterBar({
    required this.selected,
    required this.onSelected,
    required this.reviewCount,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    const List<String> filters = <String>['全部生词例句', '今日收藏', '需要复习'];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: filters
          .map((String value) {
            final bool active = value == selected;
            final bool review = value == '需要复习';
            final Color activeBg = review
                ? const Color(0xFF8F1D1D)
                : AppDesignTokens.brandGreenDark;
            final Color idleBg = review
                ? (AppDesignTokens.isDark
                      ? const Color(0xFF3A2222)
                      : const Color(0xFFFFF0F0))
                : AppDesignTokens.softGray;
            final Color idleFg = review
                ? (AppDesignTokens.isDark
                      ? const Color(0xFFFFB4B4)
                      : const Color(0xFF8F1D1D))
                : AppDesignTokens.textSecondary;
            return ChoiceChip(
              label: Text(review ? '$value ($reviewCount)' : value),
              selected: active,
              onSelected: (_) => onSelected(value),
              selectedColor: activeBg,
              backgroundColor: idleBg,
              labelStyle: TextStyle(
                color: active ? Colors.white : idleFg,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
              side: BorderSide(
                color: active
                    ? activeBg
                    : (review
                          ? (AppDesignTokens.isDark
                                ? const Color(0xFF6A3A3A)
                                : const Color(0xFFF0B7B7))
                          : AppDesignTokens.borderGray),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}
