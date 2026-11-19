import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';

class PhraseFilterChipRow extends StatelessWidget {
  const PhraseFilterChipRow({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options
              .map((String option) {
                final bool isActive = option == selected;
                return ChoiceChip(
                  label: Text(option),
                  selected: isActive,
                  onSelected: (_) => onSelected(option),
                  selectedColor: AppDesignTokens.isDark
                      ? const Color(0xFF1E3A2A)
                      : const Color(0xFFE5F5EA),
                  backgroundColor: AppDesignTokens.softGray,
                  labelStyle: TextStyle(
                    color: isActive
                        ? (AppDesignTokens.isDark
                              ? AppDesignTokens.brandGreen
                              : const Color(0xFF0F7A43))
                        : AppDesignTokens.textSecondary,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: isActive
                        ? AppDesignTokens.brandGreenDark
                        : AppDesignTokens.borderGray,
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}
