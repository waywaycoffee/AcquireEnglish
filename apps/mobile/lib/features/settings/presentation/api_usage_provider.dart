import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/api_usage_ledger.dart';

/// Keeps the ledger scoped to the signed-in email (or `local`).
final Provider<ApiUsageLedger> apiUsageLedgerProvider = Provider<ApiUsageLedger>(
  (Ref ref) {
    final ApiUsageLedger ledger = ApiUsageLedger.instance;
    final AuthSessionState auth = ref.watch(authSessionProvider);
    ledger.setAccountKey(auth.isLoggedIn ? auth.email : 'local');
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    ApiUsageLedger.cloudSync = auth.isLoggedIn
        ? (List<ApiUsageEvent> batch) async {
            await api.syncApiUsageEvents(
              batch
                  .map(
                    (ApiUsageEvent e) =>
                        Map<String, dynamic>.from(e.toJson()),
                  )
                  .toList(growable: false),
            );
          }
        : null;
    return ledger;
  },
);
