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
    'hair',
    'top',
    'bottom',
    'accessory',
    'bg',
  ];
  static const Map<String, String> _labels = <String, String>{
    'hair': '发型',
    'top': '上衣',
    'bottom': '下装',
    'accessory': '道具',
    'bg': '背景',
  };

  String _slot = 'hair';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AvatarMeDto> async = ref.watch(avatarMeProvider);
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace st) => Center(child: Text('加载失败：$e')),
          data: (AvatarMeDto me) {
            final List<CosmeticItemDto> items = me.catalog
                .where((CosmeticItemDto i) => i.slot == _slot)
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
                        '衣柜商城',
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
                            AvatarPreview(loadout: me.loadout, height: 150),
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
                                    '完成复习、跟读与口语纠错可获得积分',
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
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            for (final String slot in _slots) ...<Widget>[
                              HubPill(
                                label: _labels[slot] ?? slot,
                                selected: _slot == slot,
                                onTap: () => setState(() => _slot = slot),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
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
                            owned: item.owned ||
                                me.inventory.contains(item.sku) ||
                                item.pricePoints == 0,
                            equipped: me.loadout[_slot] == item.sku,
                            onBuy: () => unawaited(_buy(item.sku)),
                            onEquip: () => unawaited(
                              _equip(slot: _slot, sku: item.sku),
                            ),
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

  Future<void> _buy(String sku) async {
    try {
      await ref.read(avatarMeProvider.notifier).purchase(sku);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('购买成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('购买失败：$e')),
      );
    }
  }

  Future<void> _equip({required String slot, required String sku}) async {
    try {
      await ref.read(avatarMeProvider.notifier).equip(slot: slot, sku: sku);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('装备失败：$e')),
      );
    }
  }
}

class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.onBuy,
    required this.onEquip,
  });

  final CosmeticItemDto item;
  final bool owned;
  final bool equipped;
  final VoidCallback onBuy;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    return HubSurface(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: owned
                  ? const Color(0xFFE8F8D8)
                  : AppDesignTokens.skyLight,
              borderRadius: BorderRadius.circular(14),
            ),
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
                  owned
                      ? (equipped ? '已装备' : '已拥有')
                      : '${item.pricePoints} 积分',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (owned)
            TextButton(
              onPressed: equipped ? null : onEquip,
              child: Text(
                equipped ? '穿着中' : '装备',
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
