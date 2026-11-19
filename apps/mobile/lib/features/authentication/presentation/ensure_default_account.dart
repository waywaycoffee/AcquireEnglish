import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/presentation/cloud_catalog_sync.dart';
import '../data/authentication_repository.dart';
import '../data/default_account.dart';
import 'auth_session.dart';

/// If the device has no session (or still shows a legacy demo name), sign in as
/// the product default account [DefaultAccount] and pull personal cloud assets.
Future<bool> ensureDefaultAccountSignIn(WidgetRef ref) async {
  if (DefaultAccount.password.isEmpty || DefaultAccount.email.isEmpty) return false;

  final AuthSessionState auth = ref.read(authSessionProvider);
  final String name = auth.displayName.trim();
  final String email = auth.email.trim().toLowerCase();
  final bool alreadyWeiwei =
      auth.isLoggedIn &&
      email == DefaultAccount.email.toLowerCase() &&
      name.isNotEmpty &&
      name != 'Mark' &&
      name != 'Elon Musk';

  if (alreadyWeiwei) {
    return false;
  }

  try {
    await ref
        .read(authenticationRepositoryProvider)
        .login(DefaultAccount.email, DefaultAccount.password);
    final AuthSessionState next = ref.read(authSessionProvider);
    // Always persist the canonical display name for the greeting header.
    await ref
        .read(authSessionProvider.notifier)
        .signIn(
          accessToken: next.accessToken,
          email: DefaultAccount.email,
          displayName: DefaultAccount.displayName,
        );
    await syncCloudCatalogAndFeed(ref);
    return true;
  } catch (_) {
    return false;
  }
}
