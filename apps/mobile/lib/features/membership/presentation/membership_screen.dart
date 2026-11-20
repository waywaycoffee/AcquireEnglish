import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/user_assets_service.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key});

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  List<Map<String, dynamic>> _skus = [];
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic>? _assets;
  String? _selected;
  String? _error;
  String? _paymentMessage;
  bool _loading = false;
  bool _paying = false;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(acquireApiClientProvider);
      final results = await Future.wait<Object>([
        api.getAssets(),
        api.listAssetSkus(),
        api.listAssetOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _assets = results[0] as Map<String, dynamic>;
        _skus = (results[1] as List<Map<String, dynamic>>)
            .where((s) => s['currency'] == 'CNY')
            .toList();
        _orders = results[2] as List<Map<String, dynamic>>;
        _selected ??= _skus.isEmpty ? null : _skus.first['sku_code'] as String;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法获取会员信息，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(Object? cents) =>
      '¥${((cents as num? ?? 0) / 100).toStringAsFixed(2)}';

  Future<void> _pay() async {
    if (_paying || !_agreed || _selected == null) return;
    final sku = _skus.firstWhere((s) => s['sku_code'] == _selected);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('确认订单', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              Text('${sku['title']} · ${_money(sku['price_cents'])}'),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.account_balance_wallet,
                  color: Colors.green,
                ),
                title: Text('微信支付'),
                subtitle: Text('一次性付款，不自动续费'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认并前往微信'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _paying = true;
      _paymentMessage = '正在创建订单并打开微信…';
    });
    try {
      final order = await ref
          .read(userAssetsServiceProvider)
          .purchaseWithWechat(skuCode: _selected!);
      bool paid = false;
      for (var attempt = 0; attempt < 5; attempt++) {
        final orders = await ref
            .read(acquireApiClientProvider)
            .listAssetOrders();
        paid = orders.any(
          (o) => o['id'] == order['id'] && o['status'] == 'paid',
        );
        if (paid || !mounted) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (mounted)
        setState(
          () => _paymentMessage = paid
              ? '支付成功，权益已到账。'
              : '微信已返回，正在等待到账确认。请稍后刷新我的订单，勿重复付款。',
        );
    } catch (_) {
      if (mounted)
        setState(() => _paymentMessage = '支付未完成或暂时无法确认。若已扣款，请刷新订单核对；未扣款可稍后重试。');
    } finally {
      if (mounted) {
        setState(() => _paying = false);
        await _load();
      }
    }
  }

  Widget _card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    final membership = _assets?['active_membership'];
    final entitlements = (_assets?['entitlements'] as List<dynamic>?) ?? <dynamic>[];
    final memberships = entitlements.whereType<Map<String, dynamic>>().where(
      (e) => e['asset_kind'] == 'membership' && e['status'] == 'active',
    );
    final ends = memberships.isEmpty ? null : memberships.first['ends_at'];
    final expiry = DateTime.tryParse('$ends')?.toLocal();
    return Scaffold(
      appBar: AppBar(
        title: const Text('会员中心'),
        actions: [
          IconButton(
            onPressed: _loading || _paying ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新权益与订单',
          ),
        ],
      ),
      body: !loggedIn
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.workspace_premium, size: 64),
                  const Text('登录后查看会员权益与购买记录'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await context.push('/login');
                      if (mounted) await _load();
                    },
                    child: const Text('登录账号'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _card(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.workspace_premium,
                                  color: Color(0xFFE4B85C),
                                  size: 40,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  membership == null
                                      ? '开启你的 Pro 学习之旅'
                                      : 'Pro 会员已生效',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  membership == null
                                      ? '选择适合自己的学习权益'
                                      : expiry == null
                                      ? '会员有效 · 下拉刷新同步最新权益'
                                      : '有效期至 ${expiry.year}年${expiry.month}月${expiry.day}日',
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '学习积分：${(_assets?['wallet'] as Map<String, dynamic>?)?['balance_credits'] ?? 0}',
                                ),
                                for (final e
                                    in entitlements.whereType<Map<String, dynamic>>().where(
                                      (e) => e['asset_kind'] == 'coach_quota',
                                    ))
                                  Text('口语陪练剩余：${e['quantity'] ?? 0} 分钟'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '选择权益套餐',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Text('价格与权益以当前套餐为准；陪练分钟包单独购买。'),
                          if (_loading) const LinearProgressIndicator(),
                          if (_error != null)
                            _card(
                              Column(
                                children: [
                                  Text(_error!),
                                  TextButton(
                                    onPressed: _load,
                                    child: const Text('重新加载'),
                                  ),
                                ],
                              ),
                            ),
                          if (!_loading && _error == null && _skus.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('暂无可购买套餐'),
                            ),
                          for (final sku in _skus)
                            Card(
                              child: ListTile(
                                selected: _selected == sku['sku_code'],
                                leading: Icon(
                                  _selected == sku['sku_code']
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                ),
                                title: Text('${sku['title']}'),
                                subtitle: Text(
                                  sku['duration_days'] != null
                                      ? '${sku['duration_days']} 天 · 到期后手动续费'
                                      : '购买后到账 · 数量 ${sku['grant_quantity'] ?? 1}',
                                ),
                                trailing: Text(
                                  _money(sku['price_cents']),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                onTap: _paying
                                    ? null
                                    : () => setState(
                                        () => _selected =
                                            sku['sku_code'] as String,
                                      ),
                              ),
                            ),
                          CheckboxListTile(
                            value: _agreed,
                            onChanged: _paying
                                ? null
                                : (v) => setState(() => _agreed = v ?? false),
                            title: const Text('我已确认套餐价格、有效期与一次性付款方式'),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          const Text(
                            '支付完成后由服务端确认到账。续费有效期在现有有效期基础上顺延；本页面不启用自动扣费。',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed:
                                _agreed &&
                                    !_paying &&
                                    !_loading &&
                                    _error == null &&
                                    _selected != null
                                ? _pay
                                : null,
                            icon: const Icon(Icons.account_balance_wallet),
                            label: Text(_paying ? '等待支付结果…' : '使用微信支付'),
                          ),
                          if (_paymentMessage != null)
                            _card(
                              Text(
                                _paymentMessage!,
                                semanticsLabel: _paymentMessage,
                              ),
                            ),
                          const SizedBox(height: 24),
                          Text(
                            '我的订单',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Text('显示最近 50 笔订单；已扣款但未到账时，请保留订单号并联系平台客服。'),
                          if (_orders.isEmpty && !_loading)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('暂无订单'),
                            ),
                          for (final order in _orders)
                            _card(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText('订单 #${order['id']}'),
                                  Text(
                                    '${_money(order['amount_cents'])} · ${order['status'] == 'paid'
                                        ? '已支付 · 权益已到账'
                                        : order['status'] == 'pending' || order['status'] == 'created'
                                        ? '待支付 / 待确认'
                                        : order['status']}',
                                  ),
                                  Text('${order['created_at'] ?? ''}'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
