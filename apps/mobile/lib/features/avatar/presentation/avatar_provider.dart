import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/avatar_models.dart';

final AsyncNotifierProvider<AvatarMeNotifier, AvatarMeDto> avatarMeProvider =
    AsyncNotifierProvider<AvatarMeNotifier, AvatarMeDto>(AvatarMeNotifier.new);

class AvatarMeNotifier extends AsyncNotifier<AvatarMeDto> {
  @override
  Future<AvatarMeDto> build() async {
    if (!ref.watch(authSessionProvider).isLoggedIn) {
      return AvatarMeDto.empty;
    }
    try {
      return await ref.read(acquireApiClientProvider).cosmeticsMe();
    } catch (_) {
      return AvatarMeDto.empty;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading<AvatarMeDto>();
    state = await AsyncValue.guard(build);
  }

  Future<ReviewPointsEarnResult?> earn({
    required String reason,
    required String clientEventId,
  }) async {
    if (!ref.read(authSessionProvider).isLoggedIn) return null;
    try {
      final ReviewPointsEarnResult result = await ref
          .read(acquireApiClientProvider)
          .earnReviewPoints(reason: reason, clientEventId: clientEventId);
      if (result.awarded) {
        final AvatarMeDto? current = state.asData?.value;
        if (current != null) {
          state = AsyncData<AvatarMeDto>(
            AvatarMeDto(
              balance: result.balance,
              inventory: current.inventory,
              loadout: current.loadout,
              catalog: current.catalog,
            ),
          );
        } else {
          await refresh();
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> purchase(String sku) async {
    final String token = ref.read(authSessionProvider).accessToken;
    final AvatarMeDto next = await ref
        .read(acquireApiClientProvider)
        .purchaseCosmetic(sku);
    if (ref.mounted && token == ref.read(authSessionProvider).accessToken)
      state = AsyncData<AvatarMeDto>(next);
  }

  Future<void> equipSet(Map<String, String> loadout) async {
    final String token = ref.read(authSessionProvider).accessToken;
    final AvatarMeDto next = await ref
        .read(acquireApiClientProvider)
        .equipCosmeticSet(loadout);
    if (ref.mounted && token == ref.read(authSessionProvider).accessToken)
      state = AsyncData<AvatarMeDto>(next);
  }

  Future<void> equip({required String slot, String? sku}) async {
    final String token = ref.read(authSessionProvider).accessToken;
    final AvatarMeDto next = await ref
        .read(acquireApiClientProvider)
        .equipCosmetic(slot: slot, sku: sku);
    if (ref.mounted && token == ref.read(authSessionProvider).accessToken)
      state = AsyncData<AvatarMeDto>(next);
  }
}
