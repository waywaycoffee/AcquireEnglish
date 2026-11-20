import 'package:common_learn_english/features/authentication/presentation/auth_session.dart';
import 'package:common_learn_english/features/avatar/data/avatar_models.dart';
import 'package:common_learn_english/features/avatar/presentation/avatar_preview.dart';
import 'package:common_learn_english/features/avatar/presentation/avatar_shop_screen.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ShopAuth extends AuthSession {
  @override
  AuthSessionState build() =>
      const AuthSessionState(accessToken: 'shop', email: 'shop@test');
}

class ShopApi extends AcquireApiClient {
  ShopApi() : super(Dio());
  Map<String, String> loadout = {'body': 'body.cartoon1'};
  int saves = 0;
  @override
  Future<AvatarMeDto> cosmeticsMe() async => AvatarMeDto(
    balance: 0,
    inventory: const ['body.cartoon1', 'body.cartoon2'],
    loadout: loadout,
    catalog: const [
      CosmeticItemDto(
        sku: 'body.cartoon2',
        slot: 'body',
        title: '少年女生',
        pricePoints: 0,
        assetKey: '',
        owned: true,
        equipped: false,
      ),
    ],
  );
  @override
  Future<AvatarMeDto> equipCosmeticSet(Map<String, String> value) async {
    saves++;
    loadout = Map.of(value);
    return cosmeticsMe();
  }
}

void main() {
  testWidgets('free role trial does not save until explicit confirmation', (
    tester,
  ) async {
    final api = ShopApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(ShopAuth.new),
          acquireApiClientProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: AvatarShopScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('试穿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('试穿'));
    await tester.pumpAndSettle();
    expect(api.saves, 0);
    expect(api.loadout['body'], 'body.cartoon1');
    expect(
      tester
          .widgetList<AvatarPreview>(find.byType(AvatarPreview))
          .first
          .loadout['body'],
      'body.cartoon2',
    );
    await tester.ensureVisible(find.text('保存此形象'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存此形象'));
    await tester.pumpAndSettle();
    expect(api.saves, 1);
    expect(api.loadout['body'], 'body.cartoon2');
    expect(find.text('保存此形象'), findsNothing);
  });
}
