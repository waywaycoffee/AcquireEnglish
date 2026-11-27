import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/exam_generated_bank.dart';
import '../domain/exam_profile.dart';
import 'exam_profile_provider.dart';

/// Shared landing for exam skill tabs: practice / import / generate.
class ExamModulePanel extends ConsumerStatefulWidget {
  const ExamModulePanel({
    required this.skill,
    required this.title,
    required this.blurb,
    required this.practiceRoute,
    this.importRoute,
    this.importLabel = '导入习题',
    this.generateCount = 8,
    this.extraActions = const <Widget>[],
    this.embeddedInScroll = false,
    super.key,
  });

  /// grammar | cloze | reading | listening | writing | vocab | mock
  final String skill;
  final String title;
  final String blurb;
  final String practiceRoute;
  final String? importRoute;
  final String importLabel;
  final int generateCount;
  final List<Widget> extraActions;

  /// When true, use Column (parent owns scrolling).
  final bool embeddedInScroll;

  @override
  ConsumerState<ExamModulePanel> createState() => _ExamModulePanelState();
}

class _ExamModulePanelState extends ConsumerState<ExamModulePanel> {
  bool _generating = false;

  Future<void> _generate() async {
    if (_generating) return;
    final ExamProfile profile = ref.read(examProfileProvider);
    final String? familyId = profile.familyId;
    if (familyId == null || familyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择考试目标')),
      );
      return;
    }
    setState(() => _generating = true);
    try {
      final List<Map<String, dynamic>> items =
          await ref.read(acquireApiClientProvider).generateExamItems(
                familyId: familyId,
                skill: widget.skill == 'mock' ? 'mock' : widget.skill,
                count: widget.generateCount,
                gradeHint: profile.family?.label ?? '',
                cefr: profile.resolvedCefr,
              );
      if (!mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生成失败，请稍后重试')),
        );
        return;
      }
      final String bankSkill =
          widget.skill == 'mock' ? 'vocab' : widget.skill;
      final int added = await ref.read(examGeneratedBankProvider).append(
            familyId: familyId,
            skill: bankSkill,
            items: items,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成并入库 $added 组，可直接练习')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评测服务暂未开通，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final String? familyId = profile.familyId;
    final int bankCount = familyId == null
        ? 0
        : ref
            .watch(examGeneratedBankProvider)
            .itemsFor(
              familyId: familyId,
              skill: widget.skill == 'mock' ? 'vocab' : widget.skill,
            )
            .length;

    final List<Widget> children = <Widget>[
      Text(
        widget.title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: AppDesignTokens.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        widget.blurb,
        style: TextStyle(
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: AppDesignTokens.textSecondary,
        ),
      ),
      if (bankCount > 0) ...<Widget>[
        const SizedBox(height: 10),
        Text(
          '本地题库已累积 $bankCount 组（含生成/导入）',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.brandGreen,
          ),
        ),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: () => context.push(widget.practiceRoute),
        style: FilledButton.styleFrom(
          backgroundColor: AppDesignTokens.brandGreen,
          foregroundColor: AppDesignTokens.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Text(
          '开始练习',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _generating ? null : () => unawaited(_generate()),
        icon: _generating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome_rounded),
        label: Text(
          _generating
              ? '正在按考纲生成…'
              : '生成一批考纲习题（${widget.generateCount}）',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppDesignTokens.textPrimary,
          side: BorderSide(color: AppDesignTokens.borderGray),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
      if (widget.importRoute != null) ...<Widget>[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push(widget.importRoute!),
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(widget.importLabel),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppDesignTokens.textPrimary,
            side: BorderSide(color: AppDesignTokens.borderGray),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
      ...widget.extraActions,
      const SizedBox(height: 16),
      Text(
        '生成走云端题库接口，密钥只在服务器；可反复生成以扩充本地练习量。',
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: AppDesignTokens.textSecondary,
        ),
      ),
    ];

    if (widget.embeddedInScroll) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: children,
    );
  }
}
