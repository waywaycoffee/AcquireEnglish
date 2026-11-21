import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';

/// Codes aligned with `services/api/.../commerce/catalog.py` MODULE_DEFS.
const Map<String, String> kModuleTitlesZh = <String, String>{
  'exam_reading': '考试阅读',
  'exam_listening': '考试听说',
  'acquire_reading': '习得阅读',
  'acquire_listening': '习得听说',
};

bool assetsUnlockModule(Map<String, dynamic>? assets, String moduleCode) {
  if (assets == null) return false;
  final String? membership = assets['active_membership'] as String?;
  if (membership == 'pro') return true;
  final Object? unlocked = assets['unlocked_modules'];
  if (unlocked is List && unlocked.map((e) => '$e').contains(moduleCode)) {
    return true;
  }
  final Object? ents = assets['entitlements'];
  if (ents is! List) return false;
  for (final Object? row in ents) {
    if (row is! Map) continue;
    if ('${row['status']}' != 'active') continue;
    if ('${row['asset_kind']}' == 'membership' && '${row['asset_ref']}' == 'pro') {
      return true;
    }
    if ('${row['asset_kind']}' == 'module' && '${row['asset_ref']}' == moduleCode) {
      return true;
    }
  }
  return false;
}

Future<void> showModulePaywall(
  BuildContext context, {
  required String moduleCode,
}) async {
  final String title = kModuleTitlesZh[moduleCode] ?? moduleCode;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('开通「$title」', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                '体验期或 Pro 会员可使用全部模块；也可单独购买本模块或组合套餐。',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(SGRoute.membership.route);
                },
                child: const Text('去会员中心开通'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('稍后再说'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
