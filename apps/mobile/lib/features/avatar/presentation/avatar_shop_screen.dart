import '../../authentication/presentation/auth_session.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/hub_ui.dart';
import '../data/avatar_models.dart';
import 'avatar_preview.dart';
import 'avatar_provider.dart';

class AvatarShopScreen extends ConsumerStatefulWidget {
  const AvatarShopScreen({super.key});

  @override
  ConsumerState<AvatarShopScreen> createState() => _AvatarShopScreenState();
}

class _AvatarShopScreenState extends ConsumerState<AvatarShopScreen> {
  static const List<String> _slots = <String>[
    'body',
    'hair',
    'top',
    'bottom',
    'accessory',
    'bg',
  ];
  static const Map<String, String> _labels = <String, String>{
    'body': '基础角色',
    'hair': '发型',
    'top': '上衣',
    'bottom': '下装',
    'accessory': '道具',
    'bg': '背景',
  };

  String _slot = 'body';
  Map<String, String>? _preview;
  bool _busy = false;
  bool _ownedOnly = false;
  String _ageFilter = '全部';
  String _genderFilter = '全部';

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authSessionProvider.select((AuthSessionState s) => s.accessToken),
      (String? previous, String next) {
        if (previous != next)
          setState(() {
            _preview = null;
            _busy = false;
          });
      },
    );
    final AsyncValue<AvatarMeDto> async = ref.watch(avatarMeProvider);
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace st) => Center(child: Text('加载失败：$e')),
          data: (AvatarMeDto me) {
            final List<CosmeticItemDto> items = me.catalog
                .where(
                  (CosmeticItemDto i) =>
                      i.slot == _slot &&
                      _matchesTemplate(i) &&
                      (!_ownedOnly ||
                          i.owned ||
                          me.inventory.contains(i.sku) ||
                          i.pricePoints == 0),
                )
                .toList(growable: false);
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: AppDesignTokens.appWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '形象商店与背包',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: <Widget>[
                      HubSurface(
                        child: Row(
                          children: <Widget>[
                            AvatarPreview(
                              loadout: _preview ?? me.loadout,
                              height: 150,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '复习积分 ${me.balance}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: AppDesignTokens.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '完成有效学习并在一起练打卡领取积分。卡通基础套装免费，单件服装适用于经典分层形象。',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile(
                        title: const Text('只看背包中已拥有的物品'),
                        value: _ownedOnly,
                        onChanged: (bool value) =>
                            setState(() => _ownedOnly = value),
                      ),
                      if (_preview != null)
                        Row(
                          children: <Widget>[
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _preview = null),
                              child: const Text('撤销试穿'),
                            ),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await _savePreview();
                                    },
                              child: const Text('保存此形象'),
                            ),
                          ],
                        ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            for (final String slot in _slots) ...<Widget>[
                              HubPill(
                                label: _labels[slot] ?? slot,
                                selected: _slot == slot,
                                onTap: _busy
                                    ? null
                                    : () => setState(() {
                                        _slot = slot;
                                      }),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      if (_slot == 'body') ...<Widget>[
                        Wrap(
                          spacing: 6,
                          children: <Widget>[
                            for (final String age in <String>['全部', '少年', '青年'])
                              ChoiceChip(
                                label: Text('年龄：$age'),
                                selected: _ageFilter == age,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(() => _ageFilter = age),
                              ),
                          ],
                        ),
                        Wrap(
                          spacing: 6,
                          children: <Widget>[
                            for (final String gender in <String>[
                              '全部',
                              '男性',
                              '女性',
                            ])
                              ChoiceChip(
                                label: Text('风格：$gender'),
                                selected: _genderFilter == gender,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(
                                        () => _genderFilter = gender,
                                      ),
                              ),
                          ],
                        ),
                        const Text(
                          '仅用于自由筛选，不要求填写真实生日或性别。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (items.isEmpty)
                        HubSurface(
                          child: Text(
                            '暂无该分类装扮',
                            style: TextStyle(
                              color: AppDesignTokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        for (final CosmeticItemDto item in items) ...<Widget>[
                          _ShopItemRow(
                            item: item,
                            owned:
                                item.owned ||
                                me.inventory.contains(item.sku) ||
                                item.pricePoints == 0,
                            equipped: me.loadout[_slot] == item.sku,
                            onBuy: () async {
                              if (_busy) return;
                              final bool? confirm = await showDialog<bool>(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title: const Text('确认兑换'),
                                  content: Text(
                                    '${item.title} · ${item.pricePoints} 积分。兑换后永久拥有，试穿不会扣费。',
                                  ),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('确认兑换'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted)
                                await _buy(item.sku);
                            },
                            onPreview: () => _tryOn(me, item),
                            onEquip: () => _tryOn(me, item),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _matchesTemplate(CosmeticItemDto item) {
    if (_slot != 'body') return true;
    final int? n = int.tryParse(item.sku.replaceFirst('body.cartoon', ''));
    if (n == null) return _ageFilter == '全部' && _genderFilter == '全部';
    final String age = n <= 2 ? '少年' : '青年';
    final String gender = n.isOdd ? '男性' : '女性';
    return (_ageFilter == '全部' || _ageFilter == age) &&
        (_genderFilter == '全部' || _genderFilter == gender);
  }

  Future<void> _tryOn(AvatarMeDto me, CosmeticItemDto item) async {
    final Map<String, String> next = <String, String>{
      ...(_preview ?? me.loadout),
    };
    if (<String>['hair', 'top', 'bottom', 'accessory'].contains(item.slot) &&
        (next['body'] ?? '').startsWith('body.cartoon')) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('切换为经典分层形象试穿'),
          content: const Text(
            '卡通基础套装为完整形象；单件发型、服装和道具使用经典分层形象。此操作只改变预览，不会立即保存或扣费。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续试穿'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      next['body'] = 'body.default';
    }
    next[item.slot] = item.sku;
    if (mounted) setState(() => _preview = next);
  }

  Future<void> _buy(String sku) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(avatarMeProvider.notifier).purchase(sku);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('购买成功')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('购买失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePreview() async {
    if (_preview == null) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(avatarMeProvider.notifier).equipSet(_preview!);
      if (mounted) setState(() => _preview = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('装备失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.onPreview,
    required this.onBuy,
    required this.onEquip,
  });

  final CosmeticItemDto item;
  final bool owned;
  final bool equipped;
  final VoidCallback onPreview;
  final VoidCallback onBuy;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    return HubSurface(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          AvatarPreview(
            loadout: <String, String>{
              'body': item.slot == 'body' ? item.sku : 'body.default',
              if (item.slot != 'body') item.slot: item.sku,
            },
            height: 72,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  owned ? (equipped ? '已装备' : '已拥有') : '${item.pricePoints} 积分',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!owned) TextButton(onPressed: onPreview, child: const Text('试穿')),
          if (owned)
            TextButton(
              onPressed: equipped ? null : onEquip,
              child: Text(
                equipped ? '穿着中' : '试穿',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else
            FilledButton(
              onPressed: onBuy,
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '购买',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
