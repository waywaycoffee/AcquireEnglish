import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../data/api_usage_ledger.dart';

/// Keeps the ledger scoped to the signed-in email (or `local`).
final Provider<ApiUsageLedger> apiUsageLedgerProvider = Provider<ApiUsageLedger>(
  (Ref ref) {
    final ApiUsageLedger ledger = ApiUsageLedger.instance;
    final AuthSessionState auth = ref.watch(authSessionProvider);
    ledger.setAccountKey(auth.isLoggedIn ? auth.email : 'local');
    return ledger;
  },
);
