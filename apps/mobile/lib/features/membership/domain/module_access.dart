import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../reading/data/reading_catalog.dart';
import '../../sync/data/acquire_api_client.dart';
import 'free_trial_seeds.dart';

export 'free_trial_seeds.dart'
    show kModuleFreePreviewCount, kFreePersonalUploadSlotsMin;

/// Codes aligned with `services/api/.../commerce/catalog.py` MODULE_DEFS.
const Map<String, String> kModuleTitlesZh = <String, String>{
  'video': '视频模块',
  'reading': '阅读模块',
  'exam': '考试模块',
  'vocab': '单词 / 词书',
  'digital_human': '数字人模块',
  'course': '课程板块',
  // Legacy content×capability codes (older clients / cached catalogs).
  'exam_reading': '考试模块',
  'exam_listening': '考试模块',
  'acquire_reading': '阅读模块',
  'acquire_listening': '视频模块',
};

/// Always unlocked without purchase (matches API FREE_MODULE_CODES).
const Set<String> kFreeModuleCodes = <String>{'vocab', 'course'};

bool isFreePreviewIndex(int index) =>
    index >= 0 && index < kModuleFreePreviewCount;

/// Public starter / default-seed readings stay available before a module purchase.
bool isFreeReadingPreviewDocId(String docId) {
  final String id = docId.trim();
  if (id.isEmpty) return false;
  if (id.startsWith('starter-')) return true;
  if (id == kDefaultWizardOfOzEntry.stableDocId) return true;
  if (isFreeTrialCourseSeedId(id) || isFreeTrialSeedId(id)) return true;
  return false;
}

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
  final String code = moduleCode.trim();
  if (kFreeModuleCodes.contains(code)) return true;
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

/// Resolves full module unlock (Pro / trial / module 年卡·月卡).
Future<bool> resolveModuleUnlocked(WidgetRef ref, String moduleCode) async {
  if (kFreeModuleCodes.contains(moduleCode.trim())) return true;
  if (!ref.read(authSessionProvider).isLoggedIn) return false;
  try {
    final Map<String, dynamic> assets =
        await ref.read(acquireApiClientProvider).getAssets();
    if (assetsUnlockModule(assets, moduleCode)) return true;
    try {
      final Map<String, dynamic> access = await ref
          .read(acquireApiClientProvider)
          .commerceModuleAccess(moduleCode);
      return access['allowed'] == true;
    } catch (_) {
      return false;
    }
  } catch (_) {
    return false;
  }
}

/// True when the user may open this content unit (entitled or free preview).
Future<bool> resolveModuleContentAccess(
  WidgetRef ref, {
  required String moduleCode,
  bool freePreviewAllowed = false,
}) async {
  if (freePreviewAllowed) return true;
  return resolveModuleUnlocked(ref, moduleCode);
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
              Text(
                '每个板块约有 $kModuleFreePreviewCount 个免费体验内容；'
                '继续学习请开通本板块年卡，或购买 Pro 7 天卡。'
                '单词 / 词书永久免费。',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(SGRoute.membership.route);
                },
                child: const Text('去开通年卡 / 7 天卡'),
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
