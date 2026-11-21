import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../reading/data/reading_catalog.dart';

/// Codes aligned with `services/api/.../commerce/catalog.py` MODULE_DEFS.
const Map<String, String> kModuleTitlesZh = <String, String>{
  'video': '视频模块',
  'reading': '阅读模块',
  'exam': '考试模块',
  'course': '课程板块',
  // Legacy content×capability codes (older clients / cached catalogs).
  'exam_reading': '考试模块',
  'exam_listening': '考试模块',
  'acquire_reading': '阅读模块',
  'acquire_listening': '视频模块',
};

/// Public starter readings stay available before a module purchase.
bool isFreeReadingPreviewDocId(String docId) =>
    docId.startsWith('starter-') ||
    docId == kDefaultWizardOfOzEntry.stableDocId;

/// Legacy entitlement refs → current product buckets.
const Map<String, List<String>> kLegacyModuleAliases = <String, List<String>>{
  'exam_reading': <String>['exam'],
  'exam_listening': <String>['exam'],
  'acquire_reading': <String>['reading', 'course'],
  'acquire_listening': <String>['video'],
};

Set<String> entitlementRefsForModule(String moduleCode) {
  final String code = moduleCode.trim();
  if (code.isEmpty) return <String>{};
  final Set<String> refs = <String>{code};
  final List<String>? mapped = kLegacyModuleAliases[code];
  if (mapped != null) {
    refs.addAll(mapped);
  }
  for (final MapEntry<String, List<String>> entry
      in kLegacyModuleAliases.entries) {
    if (entry.value.contains(code)) {
      refs.add(entry.key);
      refs.addAll(entry.value);
    }
  }
  return refs;
}

bool assetsUnlockModule(Map<String, dynamic>? assets, String moduleCode) {
  if (assets == null) return false;
  final String? membership = assets['active_membership'] as String?;
  if (membership == 'pro') return true;
  final Set<String> accepted = entitlementRefsForModule(moduleCode);
  final Object? unlocked = assets['unlocked_modules'];
  if (unlocked is List &&
      unlocked.map((e) => '$e').any(accepted.contains)) {
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
    if ('${row['asset_kind']}' == 'module' &&
        accepted.contains('${row['asset_ref']}')) {
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
                '体验期或 Pro 会员可使用全部板块；也可单独购买本板块或组合套餐。',
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
