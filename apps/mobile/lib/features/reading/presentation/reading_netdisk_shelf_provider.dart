import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/reading_ingest.dart';
import '../data/reading_netdisk_import.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

const String kReadingNetdiskShelfKey = 'reading_netdisk_shelf_v1';

class ReadingNetdiskShelfState {
  const ReadingNetdiskShelfState({
    this.ready = false,
    this.config = const ReadingNetdiskShelfConfig(),
    this.syncing = false,
    this.liveStatus = '',
  });

  final bool ready;
  final ReadingNetdiskShelfConfig config;
  final bool syncing;
  final String liveStatus;

  /// Header line on the reading shelf. Empty until a folder is remembered.
  String get subtitle {
    if (config.folders.isEmpty && liveStatus.isEmpty) return '';
    if (syncing && liveStatus.isNotEmpty) return liveStatus;
    if (!config.autoImport) {
      if (config.lastSummary.isEmpty) return '百度网盘自动入库已关闭';
      return '自动入库已关闭 · ${config.lastSummary}';
    }
    return config.lastSummary;
  }

  ReadingNetdiskShelfState copyWith({
    bool? ready,
    ReadingNetdiskShelfConfig? config,
    bool? syncing,
    String? liveStatus,
  }) => ReadingNetdiskShelfState(
    ready: ready ?? this.ready,
    config: config ?? this.config,
    syncing: syncing ?? this.syncing,
    liveStatus: liveStatus ?? this.liveStatus,
  );
}

final NotifierProvider<ReadingNetdiskShelfNotifier, ReadingNetdiskShelfState>
readingNetdiskShelfProvider =
    NotifierProvider<ReadingNetdiskShelfNotifier, ReadingNetdiskShelfState>(
      ReadingNetdiskShelfNotifier.new,
    );

class ReadingNetdiskShelfNotifier extends Notifier<ReadingNetdiskShelfState> {
  bool _busy = false;

  @override
  ReadingNetdiskShelfState build() {
    final String account = ref.watch(studyAccountProvider);
    ref.watch(authSessionProvider);
    return ReadingNetdiskShelfState(ready: true, config: _readConfig(account));
  }

  Future<void> setAutoImport(bool enabled) async {
    await _save(state.config.copyWith(autoImport: enabled));
  }

  Future<void> watchFolder(String path) async {
    final String normalized = normalizeNetdiskFolder(path);
    if (normalized.isEmpty) return;
    if (state.config.isWatching(normalized)) {
      if (!state.config.autoImport) {
        await _save(state.config.copyWith(autoImport: true));
      }
      return;
    }
    await _save(
      state.config.copyWith(
        autoImport: true,
        folders: <String>[...state.config.folders, normalized],
      ),
    );
  }

  Future<void> unwatchFolder(String path) async {
    final String normalized = normalizeNetdiskFolder(path);
    await _save(
      state.config.copyWith(
        folders: state.config.folders
            .where((String folder) => folder != normalized)
            .toList(growable: false),
      ),
    );
  }

  /// Import an already-scanned list. Skips books already on the shelf.
  Future<NetdiskImportOutcome> importBooks(List<NetdiskEpubRef> books) async {
    if (_busy) {
      throw StateError('正在导入，请稍候');
    }
    if (!ref.read(authSessionProvider).isLoggedIn) {
      throw StateError('请先登录后再导入网盘书籍');
    }
    final String account = ref.read(studyAccountProvider);
    _busy = true;
    state = state.copyWith(syncing: true, liveStatus: '正在准备导入…');
    try {
      await _waitLibrary();
      final NetdiskImportOutcome outcome = await _importList(books);
      if (!ref.mounted || ref.read(studyAccountProvider) != account) {
        return outcome;
      }
      final String summary = summarizeNetdiskImport(outcome);
      await _commit(
        state.config.copyWith(
          lastSummary: summary,
          lastFailed: outcome.failed > 0 && outcome.imported == 0,
        ),
      );
      return outcome;
    } catch (error) {
      if (ref.mounted && ref.read(studyAccountProvider) == account) {
        await _commit(
          state.config.copyWith(
            lastSummary: '百度网盘导入失败：${netdiskErrorText(error)}',
            lastFailed: true,
          ),
        );
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  /// Scan remembered folders and import new EPUBs.
  ///
  /// Automatic calls skip when auto-import is off, nobody is signed in, a
  /// sync is already running, or the last success is still fresh. [force]
  /// still runs while auto-import is off.
  Future<NetdiskImportOutcome?> syncWatched({bool force = false}) async {
    if (_busy) return null;
    final ReadingNetdiskShelfConfig config = state.config;
    if (config.folders.isEmpty) return null;
    if (!force && !config.autoImport) return null;
    if (!ref.read(authSessionProvider).isLoggedIn) return null;
    final DateTime? last = config.lastRunAt;
    if (!force &&
        !config.lastFailed &&
        last != null &&
        DateTime.now().difference(last) < kNetdiskShelfAutoSyncGap) {
      return null;
    }
    final String account = ref.read(studyAccountProvider);
    _busy = true;
    state = state.copyWith(syncing: true, liveStatus: '正在扫描百度网盘书架…');
    try {
      await _waitLibrary();
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final List<NetdiskEpubRef> books = <NetdiskEpubRef>[];
      final List<String> scanErrors = <String>[];
      for (final String folder in config.folders) {
        try {
          final List<Map<String, dynamic>> rows = await api.scanNetdiskEpubs(
            provider: 'baidu',
            path: folder,
          );
          books.addAll(rows.map(NetdiskEpubRef.fromJson));
        } catch (error) {
          if (scanErrors.length < 3) scanErrors.add(netdiskErrorText(error));
        }
      }
      final NetdiskImportOutcome outcome = await _importList(books);
      if (!ref.mounted || ref.read(studyAccountProvider) != account) {
        return outcome;
      }
      final bool failed = scanErrors.isNotEmpty && outcome.imported == 0;
      await _commit(
        state.config.copyWith(
          lastSummary: summarizeNetdiskImport(outcome, scanErrors: scanErrors),
          lastRunAt: DateTime.now(),
          lastFailed: failed || (outcome.failed > 0 && outcome.imported == 0),
        ),
      );
      return outcome;
    } catch (error) {
      if (ref.mounted && ref.read(studyAccountProvider) == account) {
        await _commit(
          state.config.copyWith(
            lastSummary: '百度网盘同步失败：${netdiskErrorText(error)}',
            lastRunAt: DateTime.now(),
            lastFailed: true,
          ),
        );
      }
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<NetdiskImportOutcome> _importList(List<NetdiskEpubRef> books) async {
    final ReadingLibraryState library = ref.read(readingLibraryProvider);
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    return importPendingNetdiskEpubs(
      books: books,
      existing: library.userDocs,
      importCount: library.importCount,
      maxImportDocs: const ReadingQuota().maxImportDocs,
      download: (String path) =>
          api.downloadNetdiskEpub(provider: 'baidu', path: path),
      parse: (Uint8List bytes, String path) =>
          parseReadingImport(bytes, filename: path),
      save: (ReadingDoc doc) =>
          ref.read(readingLibraryProvider.notifier).addDoc(doc),
      onProgress: (NetdiskImportProgress progress) {
        if (!ref.mounted) return;
        state = state.copyWith(
          syncing: true,
          liveStatus:
              '正在导入 ${progress.index}/${progress.total} ${progress.title}',
        );
      },
    );
  }

  Future<void> _waitLibrary() async {
    for (int i = 0; i < 50; i++) {
      if (ref.read(readingLibraryProvider).ready) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!ref.mounted) return;
    }
  }

  Future<void> _save(ReadingNetdiskShelfConfig config) =>
      _commit(config, syncing: state.syncing, liveStatus: state.liveStatus);

  Future<void> _commit(
    ReadingNetdiskShelfConfig config, {
    bool syncing = false,
    String liveStatus = '',
  }) async {
    final String account = ref.read(studyAccountProvider);
    _writeConfig(account, config);
    if (!ref.mounted || ref.read(studyAccountProvider) != account) return;
    state = state.copyWith(
      ready: true,
      config: config,
      syncing: syncing,
      liveStatus: liveStatus,
    );
  }

  ReadingNetdiskShelfConfig _readConfig(String account) {
    if (!Hive.isBoxOpen('prefs')) return const ReadingNetdiskShelfConfig();
    final String? raw = Hive.box<String>(
      'prefs',
    ).get(studyStorageKey(kReadingNetdiskShelfKey, account));
    if (raw == null || raw.isEmpty) return const ReadingNetdiskShelfConfig();
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const ReadingNetdiskShelfConfig();
      return ReadingNetdiskShelfConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return const ReadingNetdiskShelfConfig();
    }
  }

  void _writeConfig(String account, ReadingNetdiskShelfConfig config) {
    if (!Hive.isBoxOpen('prefs')) return;
    Hive.box<String>('prefs').put(
      studyStorageKey(kReadingNetdiskShelfKey, account),
      jsonEncode(config.toJson()),
    );
  }
}
