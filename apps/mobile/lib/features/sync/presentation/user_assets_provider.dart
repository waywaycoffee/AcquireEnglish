import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../data/user_assets_service.dart';

final AsyncNotifierProvider<UserAssetsNotifier, UserAssetsSnapshot?>
userAssetsProvider =
    AsyncNotifierProvider<UserAssetsNotifier, UserAssetsSnapshot?>(
      UserAssetsNotifier.new,
    );

class UserAssetsNotifier extends AsyncNotifier<UserAssetsSnapshot?> {
  @override
  Future<UserAssetsSnapshot?> build() async {
    if (!ref.watch(authSessionProvider).isLoggedIn) {
      return null;
    }
    try {
      return await ref.read(userAssetsServiceProvider).fetch();
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading<UserAssetsSnapshot?>();
    state = await AsyncValue.guard(build);
  }
}
