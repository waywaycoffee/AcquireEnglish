import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/avatar_models.dart';
import 'avatar_preview.dart';
import 'avatar_provider.dart';

class AvatarShopScreen extends ConsumerStatefulWidget {
  const AvatarShopScreen({super.key});

  @override
  ConsumerState<AvatarShopScreen> createState() => _AvatarShopScreenState();
}

class _AvatarShopScreenState extends ConsumerState<AvatarShopScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _slots.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AvatarMeDto> async = ref.watch(avatarMeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('衣柜商城'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: <Tab>[
            for (final String slot in _slots) Tab(text: _labels[slot] ?? slot),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(child: Text('加载失败：$e')),
        data: (AvatarMeDto me) {
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: <Widget>[
                    AvatarPreview(loadout: me.loadout, height: 140),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '复习积分 ${me.balance}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '完成复习、跟读与口语纠错可获得积分，用来换装扮。',
                            style: TextStyle(height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: <Widget>[
                    for (final String slot in _slots)
                      _SlotList(
                        slot: slot,
                        me: me,
                        onBuy: (String sku) => unawaited(_buy(sku)),
                        onEquip: (String sku) =>
                            unawaited(_equip(slot: slot, sku: sku)),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
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

class _SlotList extends StatelessWidget {
  const _SlotList({
    required this.slot,
    required this.me,
    required this.onBuy,
    required this.onEquip,
  });

  final String slot;
  final AvatarMeDto me;
  final void Function(String sku) onBuy;
  final void Function(String sku) onEquip;

  @override
  Widget build(BuildContext context) {
    final List<CosmeticItemDto> items = me.catalog
        .where((CosmeticItemDto i) => i.slot == slot)
        .toList(growable: false);
    if (items.isEmpty) {
      return const Center(child: Text('暂无该分类装扮'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final CosmeticItemDto item = items[index];
        final bool owned =
            item.owned || me.inventory.contains(item.sku) || item.pricePoints == 0;
        final bool equipped = me.loadout[slot] == item.sku;
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: equipped
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black12,
            ),
          ),
          title: Text(item.title),
          subtitle: Text(
            owned
                ? (equipped ? '已装备' : '已拥有')
                : '${item.pricePoints} 积分',
          ),
          trailing: owned
              ? TextButton(
                  onPressed: equipped ? null : () => onEquip(item.sku),
                  child: Text(equipped ? '穿着中' : '装备'),
                )
              : FilledButton(
                  onPressed: () => onBuy(item.sku),
                  child: const Text('购买'),
                ),
        );
      },
    );
  }
}
