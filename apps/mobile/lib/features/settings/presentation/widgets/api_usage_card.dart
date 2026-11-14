import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/auth_session.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../data/api_usage_ledger.dart';
import '../api_usage_provider.dart';
import 'settings_group_card.dart';

class ApiUsageCard extends ConsumerStatefulWidget {
  const ApiUsageCard({super.key});

  @override
  ConsumerState<ApiUsageCard> createState() => _ApiUsageCardState();
}

class _ApiUsageCardState extends ConsumerState<ApiUsageCard> {
  late final ApiUsageLedger _ledger;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ledger = ApiUsageLedger.instance;
    _ledger.addListener(_onLedgerChanged);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await _ledger.ensureLoaded();
    if (!mounted) {
      return;
    }
    setState(() => _ready = true);
  }

  void _onLedgerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ledger.removeListener(_onLedgerChanged);
    super.dispose();
  }

  String _formatTokens(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return '$value';
  }

  String _formatMoneyUsd(double usd) {
    if (usd <= 0) {
      return r'$0.00';
    }
    if (usd < 0.01) {
      return r'≈$' + usd.toStringAsFixed(4);
    }
    return r'≈$' + usd.toStringAsFixed(2);
  }

  String _formatMoneyCny(double cny) {
    if (cny <= 0) {
      return '¥0.00';
    }
    if (cny < 0.01) {
      return '≈¥${cny.toStringAsFixed(4)}';
    }
    return '≈¥${cny.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final AuthSessionState auth = ref.watch(authSessionProvider);
    ref.watch(apiUsageLedgerProvider); // sync account key
    final ApiUsageSnapshot snap = _ledger.snapshotForAccount();
    final String accountLabel = auth.isLoggedIn
        ? (auth.email.isEmpty ? '已登录账号' : auth.email)
        : '本机未登录（local）';

    final List<Widget> breakdown = <Widget>[];
    final List<ApiUsageKind> kinds = ApiUsageKind.values
        .where(
          (ApiUsageKind kind) =>
              (snap.tokensByKind[kind] ?? 0) > 0 ||
              (snap.costByKind[kind] ?? 0) > 0,
        )
        .toList(growable: false);
    for (final ApiUsageKind kind in kinds) {
      final int tokens = snap.tokensByKind[kind] ?? 0;
      final double cost = snap.costByKind[kind] ?? 0;
      final double audioSec = snap.audioSecondsByKind[kind] ?? 0;
      breakdown.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  kind.labelZh,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ),
              Text(
                kind == ApiUsageKind.asr
                    ? '${(audioSec / 60).toStringAsFixed(1)} 分钟 · ${_formatMoneyCny(cost * ApiUsagePricing.usdToCny)}'
                    : '${_formatTokens(tokens)} tok · ${_formatMoneyCny(cost * ApiUsagePricing.usdToCny)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SettingsGroupCard(
      title: 'API 消耗（估算）',
      icon: Icons.receipt_long_rounded,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Text(
            '账号：$accountLabel',
            style: TextStyle(
              fontSize: 13,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ),
        if (!_ready)
          const Padding(
            padding: EdgeInsets.all(18),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _formatTokens(snap.totalTokens),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      Text(
                        '估算 tokens（输入 ${_formatTokens(snap.promptTokens)} · 输出 ${_formatTokens(snap.completionTokens)}）',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      _formatMoneyCny(snap.totalCostCny),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    Text(
                      _formatMoneyUsd(snap.totalCostUsd),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (breakdown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: breakdown,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(
              '按公开价目粗算（如 gpt-4o-mini / DeepSeek / 百炼 ASR），'
              '有官方 usage 优先用官方；本地 Whisper / 免费翻译不计费。'
              '实际以服务商账单为准。',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: snap.events.isEmpty
                    ? null
                    : () async {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: const Text('清零本账号用量？'),
                            content: const Text(
                              '只清除本机记录的估算数据，不会影响服务商账单。',
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('清零'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await _ledger.clearAccount();
                        }
                      },
                child: const Text('清零记录'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
