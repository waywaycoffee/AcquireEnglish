import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../domain/oral_expression_diagnosis.dart';

/// Live-style content diagnosis + idiomatic rewrite card.
class OralDiagnosisCard extends StatelessWidget {
  const OralDiagnosisCard({
    required this.diagnosis,
    this.onSpeakLiteral,
    this.onSpeakIdiomatic,
    this.onSave,
    this.onGrammar,
    this.saved = false,
    super.key,
  });

  final OralExpressionDiagnosis diagnosis;
  final VoidCallback? onSpeakLiteral;
  final VoidCallback? onSpeakIdiomatic;
  final VoidCallback? onSave;
  final VoidCallback? onGrammar;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final bool showStrikeFix = diagnosis.hasLiteralFix;
    final String clearLine = diagnosis.literalEn.isNotEmpty
        ? diagnosis.literalEn
        : diagnosis.idiomaticEn;
    final String idiomaticLine = diagnosis.idiomaticEn.isNotEmpty
        ? diagnosis.idiomaticEn
        : diagnosis.literalEn;

    return Material(
      color: AppDesignTokens.appWhite,
      elevation: 10,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Section(
              title: showStrikeFix ? '内容诊断' : '内容确认',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (showStrikeFix)
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: diagnosis.source,
                            style: const TextStyle(
                              color: Color(0xFFE11D48),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Color(0xFFE11D48),
                              height: 1.35,
                            ),
                          ),
                          if (clearLine.isNotEmpty) ...<InlineSpan>[
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: clearLine,
                              style: const TextStyle(
                                color: Color(0xFF16A34A),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    Text(
                      clearLine.isNotEmpty ? clearLine : diagnosis.source,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  if (!showStrikeFix) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      diagnosis.tip.isNotEmpty
                          ? diagnosis.tip
                          : '这样说意思已经清楚，可继续对话。',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _ActionRow(
                    onSpeak: onSpeakLiteral,
                    onSave: onSave,
                    onCopy: () => _copy(
                      context,
                      clearLine.isNotEmpty ? clearLine : diagnosis.source,
                    ),
                    onGrammar: onGrammar,
                    saved: saved,
                  ),
                ],
              ),
            ),
            if (diagnosis.hasIdiomaticPolish ||
                (showStrikeFix && idiomaticLine.isNotEmpty)) ...<Widget>[
              const SizedBox(height: 14),
              _Section(
                title: '地道表达',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      idiomaticLine.isNotEmpty
                          ? idiomaticLine
                          : '先用英文说清楚刚才的意思',
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    if (diagnosis.tip.isNotEmpty && showStrikeFix) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        diagnosis.tip,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _ActionRow(
                      onSpeak: onSpeakIdiomatic,
                      onSave: onSave,
                      onCopy: () => _copy(context, idiomaticLine),
                      onGrammar: onGrammar,
                      saved: saved,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    if (text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    this.onSpeak,
    this.onSave,
    this.onCopy,
    this.onGrammar,
    this.saved = false,
  });

  final VoidCallback? onSpeak;
  final VoidCallback? onSave;
  final VoidCallback? onCopy;
  final VoidCallback? onGrammar;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: '朗读',
          onPressed: onSpeak,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.volume_up_rounded, size: 20),
        ),
        IconButton(
          tooltip: saved ? '已收藏到语言库' : '收藏地道表达',
          onPressed: onSave,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            saved ? Icons.star_rounded : Icons.star_border_rounded,
            size: 20,
            color: saved ? const Color(0xFFF59E0B) : null,
          ),
        ),
        IconButton(
          tooltip: '复制',
          onPressed: onCopy,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy_rounded, size: 18),
        ),
        TextButton.icon(
          onPressed: onGrammar,
          icon: const Icon(Icons.visibility_outlined, size: 16),
          label: const Text('语法解析'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF6D28D9),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
