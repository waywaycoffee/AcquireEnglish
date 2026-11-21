import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
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
  List<Map<String, dynamic>> _modules = [];
  List<Map<String, dynamic>> _combos = [];
  Map<String, dynamic>? _assets;
  Map<String, dynamic>? _trial;
  String? _selected;
  String? _error;
  String? _paymentMessage;
  bool _loading = false;
  bool _paying = false;
  Map<String, dynamic>? _rewards;
  int? _couponId;
  bool _rewardBusy = false;
  bool _trialBusy = false;

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
        api.membershipRewards(),
      ]);
      Map<String, dynamic>? trial;
      Map<String, dynamic>? catalog;
      try {
        trial = await api.commerceTrialStatus();
      } catch (_) {
        trial = null;
      }
      try {
        catalog = await api.commerceCatalog();
      } catch (_) {
        catalog = null;
      }
      if (!mounted) return;
      setState(() {
        _rewards = results[3] as Map<String, dynamic>;
        _assets = results[0] as Map<String, dynamic>;
        _trial = trial;
        _modules = ((catalog?['modules'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _combos = ((catalog?['combos'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _skus = (results[1] as List<Map<String, dynamic>>)
            .where((s) => s['currency'] == 'CNY' && s['kind'] == 'membership')
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

  int? _trialDaysLeft() {
    final ends = DateTime.tryParse('${_trial?['trial_ends_at'] ?? ''}');
    if (ends == null) return null;
    final diff = ends.toUtc().difference(DateTime.now().toUtc());
    if (diff.isNegative) return 0;
    return diff.inDays + 1;
  }

  Future<void> _claimTrialExtend() async {
    if (_trialBusy) return;
    setState(() => _trialBusy = true);
    try {
      await ref.read(acquireApiClientProvider).commerceClaimTrialExtend();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已领取 7 天全功能延长券，可在下方优惠券兑换')),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('领取失败：需体验期内每天登录满 7 天，且未领取过')),
        );
      }
    } finally {
      if (mounted) setState(() => _trialBusy = false);
    }
  }

  Widget _trialBanner() {
    final inTrial = _trial?['in_trial'] == true;
    if (!inTrial && _trial == null) return const SizedBox.shrink();
    if (!inTrial) return const SizedBox.shrink();
    final daysLeft = _trialDaysLeft();
    final loginDays = (_trial?['login_days'] as num?)?.toInt() ?? 0;
    final required = (_trial?['required_login_days'] as num?)?.toInt() ?? 7;
    final eligible = _trial?['extend_eligible'] == true;
    final claimed = _trial?['extend_claimed'] == true;
    final used = _trial?['extend_coupon_used'] == true;
    final message = '${_trial?['message'] ?? ''}';
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('全功能体验', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            daysLeft == null
                ? '体验进行中'
                : '剩余约 $daysLeft 天 · 登录 $loginDays / $required 天',
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: (!eligible || claimed || used || _trialBusy || _paying)
                ? null
                : _claimTrialExtend,
            child: Text(
              used
                  ? '延长券已兑换'
                  : claimed
                  ? '延长券已领取'
                  : eligible
                  ? '领取 +7 天延长券'
                  : '连续登录可领延长券',
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleCatalog() {
    if (_modules.isEmpty && _combos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('学习模块', style: Theme.of(context).textTheme.titleLarge),
        const Text('按考试/习得 × 阅读/听说拆分；可单模块或组合开通。'),
        for (final mod in _modules)
          Card(
            child: ListTile(
              title: Text('${mod['title']}'),
              subtitle: Text(
                '${mod['blurb'] ?? ''}\n月付 ${_money(mod['monthly_cents'])}（标价 ${_money(mod['list_cents'])}）',
              ),
              isThreeLine: true,
            ),
          ),
        if (_combos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('组合优惠', style: Theme.of(context).textTheme.titleMedium),
          for (final combo in _combos)
            Card(
              child: ListTile(
                title: Text('${combo['title']}'),
                subtitle: Text(
                  '${combo['duration_days'] ?? ''} 天'
                  '${combo['pick'] != null ? ' · 任选 ${combo['pick']} 模块' : ''}',
                ),
                trailing: Text(
                  _money(combo['price_cents']),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _money(Object? cents) =>
      '¥${((cents as num? ?? 0) / 100).toStringAsFixed(2)}';

  Future<void> _pay() async {
    if (_paying) return;
    if (_selected == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('套餐尚未加载，请刷新后选择套餐。')));
      return;
    }
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
              Text(_couponId == null ? '未使用抵扣券' : '已选择抵扣券，以服务端结算金额为准'),
              const Text('确认即表示同意当前价格和有效期；一次性付款，不自动续费。'),
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
          .purchaseWithWechat(skuCode: _selected!, couponId: _couponId);
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
    } catch (error) {
      String message = '支付未完成。若已扣款请刷新订单，勿重复付款。';
      if (error is DioException) {
        final data = error.response?.data;
        message = data is Map && data['detail'] != null
            ? '${data['detail']}'
            : '无法连接支付服务，请检查网络后重试。';
      } else if (error is StateError) {
        message = '${error.message}';
      }
      if (mounted) {
        setState(() => _paymentMessage = message);
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('暂未完成支付'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _paying = false);
        await _load();
      }
    }
  }

  Future<void> _rewardAction(Future<void> Function() action) async {
    setState(() => _rewardBusy = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，可能已领取或学习时长不足，请刷新后重试。')),
        );
    } finally {
      if (mounted) setState(() => _rewardBusy = false);
    }
  }

  Widget _rewardCard() {
    final coupons = (_rewards?['coupons'] as List<dynamic>?) ?? [];
    final rewards = (_rewards?['rewards'] as List<dynamic>?) ?? [];
    final minutes = (_rewards?['study_minutes'] as num?)?.toInt() ?? 0;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('学习赚会员', style: Theme.of(context).textTheme.titleLarge),
          Text('已同步学习 $minutes 分钟 · 每档奖励限领一次'),
          const Text('时长券领取后兑换生效；现金券仅抵扣会员订单，满10元可用，不提现、不叠加。提交订单即占用，请勿重复下单。'),
          for (final reward in rewards)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${reward['title']}'),
              subtitle: Text('进度 $minutes / ${reward['minutes']} 分钟'),
              trailing: TextButton(
                onPressed:
                    _rewardBusy ||
                        _paying ||
                        minutes < (reward['minutes'] as num) ||
                        coupons.any((c) => c['code'] == reward['code']) ||
                        (reward['code'] == 'welcome' &&
                            _assets?['active_membership'] != null)
                    ? null
                    : () => _rewardAction(
                        () => ref
                            .read(acquireApiClientProvider)
                            .claimMembershipReward('${reward['code']}'),
                      ),
                child: Text(
                  coupons.any((c) => c['code'] == reward['code'])
                      ? '已领取'
                      : '领取',
                ),
              ),
            ),
          const Divider(),
          const Text('我的优惠券'),
          if (coupons.isEmpty) const Text('暂无优惠券，完成学习即可领取'),
          for (final coupon in coupons)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                coupon['kind'] == 'days'
                    ? '会员 ${coupon['value']} 天券'
                    : '${_money(coupon['value'])} 会员抵扣券',
              ),
              trailing: TextButton(
                onPressed: coupon['used'] == true || _rewardBusy || _paying
                    ? null
                    : () {
                        if (coupon['kind'] == 'days') {
                          _rewardAction(
                            () => ref
                                .read(acquireApiClientProvider)
                                .redeemMembershipCoupon(coupon['id'] as int),
                          );
                        } else {
                          setState(
                            () => _couponId = _couponId == coupon['id']
                                ? null
                                : coupon['id'] as int,
                          );
                        }
                      },
                child: Text(
                  coupon['used'] == true
                      ? '已使用 / 已占用'
                      : coupon['kind'] == 'days'
                      ? '立即兑换'
                      : _couponId == coupon['id']
                      ? '取消选择'
                      : '用于购卡',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    final membership = _assets?['active_membership'];
    final entitlements =
        (_assets?['entitlements'] as List<dynamic>?) ?? <dynamic>[];
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
                                    in entitlements
                                        .whereType<Map<String, dynamic>>()
                                        .where(
                                          (e) =>
                                              e['asset_kind'] == 'coach_quota',
                                        ))
                                  Text('口语陪练剩余：${e['quantity'] ?? 0} 分钟'),
                              ],
                            ),
                          ),
                          _trialBanner(),
                          _moduleCatalog(),
                          _rewardCard(),
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
                          const Text(
                            '支付完成后由服务端确认到账。续费有效期在现有有效期基础上顺延；本页面不启用自动扣费。',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _paying ? null : _pay,
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
