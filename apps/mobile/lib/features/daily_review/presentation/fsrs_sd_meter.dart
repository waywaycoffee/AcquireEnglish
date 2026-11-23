import 'package:flutter/material.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/daily_review.dart';

/// Compact FSRS Stability / Difficulty meters for review & word detail.
class FsrsSdMeter extends StatelessWidget {
  const FsrsSdMeter({
    required this.record,
    this.compact = false,
    super.key,
  });

  final ReviewRecord record;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fsrs.Card card = record.card;
    final double rawStability = card.stability ?? 0;
    final double rawDifficulty = card.difficulty ?? 5;
    final double stability = rawStability.isFinite
        ? rawStability.clamp(0, 365).toDouble()
        : 0;
    final double difficulty = rawDifficulty.isFinite
        ? rawDifficulty.clamp(1, 10).toDouble()
        : 5;
    // Normalize: stability 0–90 days → bar; difficulty 1–10 → bar.
    final double sNorm = (stability / 90).clamp(0.0, 1.0);
    final double dNorm = ((difficulty - 1) / 9).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: AppDesignTokens.softGray,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            compact ? '记忆曲线' : 'FSRS · 稳定性 / 难度',
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _MeterRow(
            label: 'S 稳定',
            valueLabel: stability < 1
                ? '${(stability * 24).toStringAsFixed(0)}h'
                : '${stability.toStringAsFixed(stability < 10 ? 1 : 0)}d',
            progress: sNorm,
            color: const Color(0xFF16A34A),
          ),
          const SizedBox(height: 6),
          _MeterRow(
            label: 'D 难度',
            valueLabel: difficulty.toStringAsFixed(1),
            progress: dNorm,
            color: const Color(0xFFEA580C),
          ),
        ],
      ),
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({
    required this.label,
    required this.valueLabel,
    required this.progress,
    required this.color,
  });

  final String label;
  final String valueLabel;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppDesignTokens.appWhite,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            valueLabel,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
