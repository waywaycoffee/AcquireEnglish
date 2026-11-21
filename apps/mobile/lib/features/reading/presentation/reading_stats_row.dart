import 'package:flutter/material.dart';

/// One compact row, with full values available to accessibility and long press.
class ReadingStatsRow extends StatelessWidget {
  const ReadingStatsRow({required this.values, super.key});

  final Map<String, int> values;

  static String compact(int value) =>
      value >= 10000 ? '${(value / 10000).toStringAsFixed(1)}万' : '$value';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          for (final entry in values.entries) ...[
            if (entry.key != values.keys.first)
              SizedBox(
                height: 18,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colors.outlineVariant,
                ),
              ),
            Expanded(
              child: Tooltip(
                message: '${entry.key}：${entry.value}',
                child: Semantics(
                  label: '${entry.key}，${entry.value}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 24,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              compact(entry.value),
                              style: TextStyle(
                                fontSize: 20,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 14,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
