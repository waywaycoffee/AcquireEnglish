import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';

/// Per-account last-seen cloud revision for document backups.
class DocumentRevisionStore {
  static String _key(String domain, String account) =>
      studyStorageKey('sync_rev_$domain', account);

  static int read(String domain, String account) {
    if (!Hive.isBoxOpen('prefs') || account.isEmpty) return 0;
    return int.tryParse(
          Hive.box<String>('prefs').get(_key(domain, account)) ?? '',
        ) ??
        0;
  }

  static Future<void> write(String domain, String account, int revision) async {
    if (!Hive.isBoxOpen('prefs') || account.isEmpty) return;
    await Hive.box<String>('prefs').put(_key(domain, account), '$revision');
  }
}
