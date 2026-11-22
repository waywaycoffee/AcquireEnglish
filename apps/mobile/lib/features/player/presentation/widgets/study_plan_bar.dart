import 'package:flutter/material.dart';

import 'study_shell_tokens.dart';

enum StudyPlanStep { watch, intensive, output, review }

extension StudyPlanStepLabel on StudyPlanStep {
  String get label => switch (this) {
        StudyPlanStep.watch => '看懂',
        StudyPlanStep.intensive => '精读',
        StudyPlanStep.output => '输出',
        StudyPlanStep.review => '复习',
      };
}

/// Lightweight guided steps above study mode tabs (video = skippable).
class StudyPlanBar extends StatelessWidget {
  const StudyPlanBar({
    required this.current,
    required this.completed,
    required this.onSelect,
    this.strict = false,
    super.key,
  });

  final StudyPlanStep current;
  final Set<StudyPlanStep> completed;
  final ValueChanged<StudyPlanStep> onSelect;

  /// Drama mode: unfinished prior steps show lock affordance (still tappable).
  final bool strict;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: <Widget>[
          for (final StudyPlanStep step in StudyPlanStep.values) ...<Widget>[
            if (step != StudyPlanStep.watch)
              Expanded(
                child: Container(
                  height: 2,
                  color: completed.contains(step) || current.index >= step.index
                      ? colors.accent.withValues(alpha: 0.45)
                      : colors.border.withValues(alpha: 0.5),
                ),
              ),
            _StepChip(
              index: step.index + 1,
              label: step.label,
              selected: current == step,
              done: completed.contains(step),
              locked: strict &&
                  step.index > 0 &&
                  !completed.contains(StudyPlanStep.values[step.index - 1]) &&
                  current != step,
              accent: colors.accent,
              onTap: () => onSelect(step),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.index,
    required this.label,
    required this.selected,
    required this.done,
    required this.locked,
    required this.accent,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool selected;
  final bool done;
  final bool locked;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? accent
                      : done
                          ? accent.withValues(alpha: 0.2)
                          : Colors.transparent,
                  border: Border.all(
                    color: selected || done
                        ? accent
                        : Theme.of(context).dividerColor,
                  ),
                ),
                child: done && !selected
                    ? Icon(Icons.check, size: 14, color: accent)
                    : locked
                        ? Icon(
                            Icons.lock_outline,
                            size: 12,
                            color: Theme.of(context).hintColor,
                          )
                        : Text(
                            '$index',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? accent : Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
