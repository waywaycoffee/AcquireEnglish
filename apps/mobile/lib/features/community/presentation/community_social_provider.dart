import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';

final communitySocialProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((Ref ref) async {
      if (!ref.watch(authSessionProvider).isLoggedIn)
        return <String, dynamic>{};
      return ref.read(acquireApiClientProvider).socialRequest('GET', '');
    });
