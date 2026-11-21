import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../../../router/app_router.dart';
import '../../../shared/audio/success_sfx.dart';
import '../../../sync/presentation/cloud_catalog_sync.dart';
import '../../domain/login_response.dart';
import '../account_hub_sheet.dart';

const String kWechatMockCodeKey = 'wechat_mock_auth_code';

Future<String> loadOrCreateWechatMockCode() async {
  if (!Hive.isBoxOpen('prefs')) {
    return 'mock_device_${DateTime.now().millisecondsSinceEpoch}';
  }
  final Box<String> box = Hive.box<String>('prefs');
  final String? existing = box.get(kWechatMockCodeKey);
  if (existing != null && existing.trim().isNotEmpty) {
    return existing.trim();
  }
  final String created =
      'mock_device_${DateTime.now().millisecondsSinceEpoch}';
  await box.put(kWechatMockCodeKey, created);
  return created;
}

Future<void> saveWechatMockCode(String code) async {
  final String trimmed = code.trim();
  if (trimmed.isEmpty || !Hive.isBoxOpen('prefs')) {
    return;
  }
  await Hive.box<String>('prefs').put(kWechatMockCodeKey, trimmed);
}

Future<void> completeLoginAndGoHome(
  WidgetRef ref,
  BuildContext context,
  LoginResponse result, {
  required bool isNew,
}) async {
  if (!context.mounted || result.token.isEmpty) {
    return;
  }
  await setSkipDefaultAccountLogin(skip: false);
  if (!context.mounted) {
    return;
  }
  if (isNew) {
    playSuccessSfx(SuccessSfxKind.fanfare);
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        isNew
            ? '欢迎加入！已赠送 1 个月 Pro，全功能免费畅用'
            : '正在同步云端视频与字幕…',
      ),
      duration: Duration(seconds: isNew ? 5 : 3),
    ),
  );
  ref.invalidate(cloudCatalogSyncProvider);
  unawaited(syncCloudCatalogAndFeed(ref));
  if (!context.mounted) {
    return;
  }
  context.go(SGRoute.home.route);
}
