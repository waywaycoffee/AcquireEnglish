import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

import '../../../constants/endpoints.dart';
import '../../authentication/presentation/account_storage.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../exam/data/exam_error_book_store.dart';
import '../../exam/domain/exam_profile.dart';
import '../../exam/presentation/exam_profile_provider.dart';
import '../../reading/data/reading_vocab_lists.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../words/domain/word_review_settings.dart';
import '../../words/presentation/word_book_provider.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../../writing/data/writing_draft_store.dart';
import '../../writing/domain/writing_models.dart';
import 'acquire_api_client.dart';
import 'document_revision_store.dart';
import 'phrase_sync_service.dart';
import 'progress_sync_service.dart';
import 'reading_library_merge.dart';
import 'vocab_sync_service.dart';
import 'wordbook_merge.dart';

const List<String> kLearningModuleKinds = <String>[
  'ipa',
  'phonics',
  'chunks',
  'listening',
  'dialogue',
];

/// Pull (and optionally push) all cross-device study domains after login/resume.
Future<void> runDeviceSyncBootstrap(
  dynamic ref, {
  bool pushLocal = false,
}) async {
  final AuthSessionState session = ref.read(authSessionProvider) as AuthSessionState;
  if (!session.isLoggedIn || session.accessToken.isEmpty) return;
  final String account = ref.read(studyAccountProvider) as String;
  final AcquireApiClient api =
      ref.read(acquireApiClientProvider) as AcquireApiClient;

  Map<String, dynamic> status = <String, dynamic>{};
  try {
    status = await api.syncStatus(token: session.accessToken);
  } catch (_) {}

  await Future.wait(<Future<void>>[
    _safe(() async {
      await (ref.read(progressSyncServiceProvider) as ProgressSyncService)
          .pullIndexed();
    }),
    _safe(() async {
      await (ref.read(vocabSyncServiceProvider) as VocabSyncService)
          .pullAndMerge();
    }),
    _safe(() async {
      await (ref.read(phraseSyncServiceProvider) as PhraseSyncService)
          .pullAndMerge();
    }),
    _safe(() => _syncReadingBackup(ref, api, session.accessToken, account, status, pushLocal)),
    _safe(() => _syncWordbookBackup(ref, api, session.accessToken, account, status, pushLocal)),
    _safe(() => _syncAppSettingsBackup(ref, api, session.accessToken, account, status, pushLocal)),
    _safe(() => _syncLearningModules(ref, api, status, pushLocal)),
    _safe(() async {
      await (ref.read(dailyReviewProvider.notifier) as dynamic)
          .syncCloudBackup();
    }),
  ]);

  if (pushLocal) {
    await _safe(() async {
      await (ref.read(vocabSyncServiceProvider) as VocabSyncService)
          .pushAllFavorites();
    });
    await _safe(() async {
      await (ref.read(phraseSyncServiceProvider) as PhraseSyncService).pushAll();
    });
  }
}

Future<void> _safe(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {}
}

Map<String, Object?> _asObjectMap(Map<dynamic, dynamic> item) =>
    <String, Object?>{
      for (final MapEntry<dynamic, dynamic> e in item.entries) '${e.key}': e.value,
    };

Future<void> _syncReadingBackup(
  dynamic ref,
  AcquireApiClient api,
  String token,
  String account,
  Map<String, dynamic> status,
  bool pushLocal,
) async {
  final int remoteRev = (status['reading'] as num?)?.toInt() ?? -1;
  final int localRev = DocumentRevisionStore.read('reading', account);
  final ReadingLibraryState library =
      ref.read(readingLibraryProvider) as ReadingLibraryState;
  final ReadingVocabLists lists =
      ref.read(readingVocabListsProvider) as ReadingVocabLists;
  ReadingLibrarySnapshot local = ReadingLibrarySnapshot(
    docs: library.userDocs,
    progress: library.progress,
    vocabLists: lists,
  );

  ({int revision, Map<String, dynamic>? state}) cloud;
  if (remoteRev == 0 && localRev == 0 && local.docs.isEmpty && local.progress.isEmpty) {
    return;
  }
  if (remoteRev >= 0 && remoteRev == localRev && !pushLocal) {
    // Still pull if we have never applied (empty local shelf).
    if (local.docs.isNotEmpty || local.progress.isNotEmpty) return;
  }

  try {
    cloud = await api.documentBackup(
      Endpoints.readingBackup,
      token: token,
    );
  } catch (_) {
    return;
  }

  final ReadingLibrarySnapshot? remote = cloud.state == null
      ? null
      : ReadingLibrarySnapshot.fromStateJson(cloud.state!);

  if (remote != null) {
    final ReadingLibrarySnapshot merged = mergeReadingLibraries(local, remote);
    await (ref.read(readingLibraryProvider.notifier) as ReadingLibraryNotifier)
        .replaceUserLibraryFromCloud(
          userDocs: merged.docs,
          progress: merged.progress,
        );
    await (ref.read(readingVocabListsProvider.notifier)
            as ReadingVocabListsNotifier)
        .replaceFromCloud(merged.vocabLists);
    local = merged;
  }

  await DocumentRevisionStore.write('reading', account, cloud.revision);

  if (!pushLocal && remote != null && cloud.revision == localRev) return;

  final ReadingLibrarySnapshot upload = shrinkReadingSnapshotForUpload(local);
  try {
    final uploaded = await api.documentBackup(
      Endpoints.readingBackup,
      token: token,
      revision: cloud.revision,
      state: upload.toStateJson(),
    );
    await DocumentRevisionStore.write('reading', account, uploaded.revision);
  } on DioException catch (error) {
    if (error.response?.statusCode == 409) {
      final again = await api.documentBackup(
        Endpoints.readingBackup,
        token: token,
      );
      if (again.state != null) {
        final ReadingLibrarySnapshot merged = mergeReadingLibraries(
          local,
          ReadingLibrarySnapshot.fromStateJson(again.state!),
        );
        await (ref.read(readingLibraryProvider.notifier)
                as ReadingLibraryNotifier)
            .replaceUserLibraryFromCloud(
              userDocs: merged.docs,
              progress: merged.progress,
            );
        await (ref.read(readingVocabListsProvider.notifier)
                as ReadingVocabListsNotifier)
            .replaceFromCloud(merged.vocabLists);
        final uploaded = await api.documentBackup(
          Endpoints.readingBackup,
          token: token,
          revision: again.revision,
          state: shrinkReadingSnapshotForUpload(merged).toStateJson(),
        );
        await DocumentRevisionStore.write('reading', account, uploaded.revision);
      }
    }
  }
}

Future<void> _syncWordbookBackup(
  dynamic ref,
  AcquireApiClient api,
  String token,
  String account,
  Map<String, dynamic> status,
  bool pushLocal,
) async {
  final int remoteRev = (status['wordbook'] as num?)?.toInt() ?? -1;
  final int localRev = DocumentRevisionStore.read('wordbook', account);
  List<WordEntry> local =
      List<WordEntry>.from(ref.read(wordBookProvider) as List<WordEntry>);

  Map<String, dynamic>? streak;
  if (Hive.isBoxOpen('prefs')) {
    final String? raw = Hive.box<String>('prefs').get('word_review_streak_v1');
    if (raw != null && raw.isNotEmpty) {
      try {
        streak = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
  }

  if (remoteRev == 0 && localRev == 0 && local.isEmpty) return;
  if (remoteRev >= 0 && remoteRev == localRev && !pushLocal && local.isNotEmpty) {
    return;
  }

  late final ({int revision, Map<String, dynamic>? state}) cloud;
  try {
    cloud = await api.documentBackup(Endpoints.wordbookBackup, token: token);
  } catch (_) {
    return;
  }

  if (cloud.state != null) {
    final Object? rawEntries = cloud.state!['entries'];
    final List<WordEntry> remote = <WordEntry>[];
    if (rawEntries is List) {
      for (final Object? item in rawEntries) {
        if (item is! Map) continue;
        try {
          remote.add(WordEntry.fromJson(_asObjectMap(item)));
        } catch (_) {}
      }
    }
    local = mergeWordBooks(local, remote);
    await (ref.read(wordBookProvider.notifier) as WordBookNotifier)
        .replaceFromCloud(local);

    final Object? remoteStreak = cloud.state!['streak'];
    if (remoteStreak is Map && Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(
        'word_review_streak_v1',
        jsonEncode(remoteStreak),
      );
      streak = Map<String, dynamic>.from(remoteStreak);
    }
  }

  await DocumentRevisionStore.write('wordbook', account, cloud.revision);

  final Map<String, dynamic> payload = <String, dynamic>{
    'version': 1,
    'entries': local.map((WordEntry e) => e.toJson()).toList(),
    if (streak != null) 'streak': streak,
  };

  try {
    final uploaded = await api.documentBackup(
      Endpoints.wordbookBackup,
      token: token,
      revision: cloud.revision,
      state: payload,
    );
    await DocumentRevisionStore.write('wordbook', account, uploaded.revision);
  } on DioException catch (error) {
    if (error.response?.statusCode != 409) return;
    final again = await api.documentBackup(Endpoints.wordbookBackup, token: token);
    if (again.state == null) return;
    final Object? rawEntries = again.state!['entries'];
    final List<WordEntry> remote = <WordEntry>[];
    if (rawEntries is List) {
      for (final Object? item in rawEntries) {
        if (item is! Map) continue;
        try {
          remote.add(WordEntry.fromJson(_asObjectMap(item)));
        } catch (_) {}
      }
    }
    final List<WordEntry> merged = mergeWordBooks(local, remote);
    await (ref.read(wordBookProvider.notifier) as WordBookNotifier)
        .replaceFromCloud(merged);
    final uploaded = await api.documentBackup(
      Endpoints.wordbookBackup,
      token: token,
      revision: again.revision,
      state: <String, dynamic>{
        'version': 1,
        'entries': merged.map((WordEntry e) => e.toJson()).toList(),
        if (streak != null) 'streak': streak,
      },
    );
    await DocumentRevisionStore.write('wordbook', account, uploaded.revision);
  }
}

Future<void> _syncAppSettingsBackup(
  dynamic ref,
  AcquireApiClient api,
  String token,
  String account,
  Map<String, dynamic> status,
  bool pushLocal,
) async {
  final int remoteRev = (status['appSettings'] as num?)?.toInt() ?? -1;
  final int localRev = DocumentRevisionStore.read('appSettings', account);

  final LearningSettingsNotifier settingsNotifier =
      ref.read(learningSettingsProvider.notifier) as LearningSettingsNotifier;
  final Map<String, Object?> localSettings = settingsNotifier.toSyncJson();
  final String localBiliCookie =
      '${localSettings['bilibiliSessdata'] ?? ''}'.trim();

  if (remoteRev >= 0 && remoteRev == localRev && !pushLocal) return;

  late final ({int revision, Map<String, dynamic>? state}) cloud;
  try {
    cloud = await api.documentBackup(Endpoints.appSettingsBackup, token: token);
  } catch (_) {
    return;
  }

  bool cloudMissingBiliCookie = false;
  if (cloud.state != null) {
    final Object? ls = cloud.state!['learningSettings'];
    if (ls is Map && ls.isNotEmpty) {
      final String cloudCookie =
          '${ls['bilibiliSessdata'] ?? ''}'.trim();
      cloudMissingBiliCookie =
          localBiliCookie.isNotEmpty && cloudCookie.isEmpty;
      await settingsNotifier.applyFromCloud(Map<String, dynamic>.from(ls));
    }
    final Object? wr = cloud.state!['wordReviewPrefs'];
    if (wr is Map && wr.isNotEmpty) {
      await (ref.read(wordReviewSettingsProvider.notifier)
              as WordReviewSettingsNotifier)
          .replaceFromCloud(
            WordReviewSettings.fromJson(Map<String, dynamic>.from(wr)),
          );
    }
    final Object? exam = cloud.state!['examProfile'];
    if (exam is Map && exam.isNotEmpty) {
      await (ref.read(examProfileProvider.notifier) as ExamProfileNotifier)
          .replaceFromCloud(
            ExamProfile.fromJson(Map<String, dynamic>.from(exam)),
          );
    }
    final Object? errors = cloud.state!['examErrorBook'];
    if (errors is List) {
      await (ref.read(examErrorBookProvider.notifier) as ExamErrorBookNotifier)
          .replaceFromCloud(
            errors
                .whereType<Map>()
                .map(
                  (Map e) =>
                      ExamErrorItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false),
          );
    }
    final Object? drafts = cloud.state!['writingDrafts'];
    if (drafts is List) {
      await (ref.read(writingDraftsProvider.notifier) as WritingDraftStore)
          .replaceFromCloud(
            drafts
                .whereType<Map>()
                .map(
                  (Map e) => WritingDraft.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false),
          );
    }
  }

  await DocumentRevisionStore.write('appSettings', account, cloud.revision);

  final Map<String, dynamic> payload = <String, dynamic>{
    'version': 1,
    'learningSettings': settingsNotifier.toSyncJson(),
    'wordReviewPrefs':
        (ref.read(wordReviewSettingsProvider) as WordReviewSettings).toJson(),
    'examProfile': (ref.read(examProfileProvider) as ExamProfile).toJson(),
    'examErrorBook': (ref.read(examErrorBookProvider) as List<ExamErrorItem>)
        .map((ExamErrorItem e) => e.toJson())
        .toList(growable: false),
    'writingDrafts': (ref.read(writingDraftsProvider) as List<WritingDraft>)
        .map((WritingDraft e) => e.toJson())
        .toList(growable: false),
  };

  // If cloud was empty and local has data, or explicit push, upload.
  // Also push when cloud settings omitted B 站 Cookie but this device has one.
  final bool shouldUpload = pushLocal ||
      cloud.state == null ||
      cloudMissingBiliCookie ||
      ((localSettings.isNotEmpty) && cloud.revision == localRev);
  if (!shouldUpload && cloud.state != null) return;

  try {
    final uploaded = await api.documentBackup(
      Endpoints.appSettingsBackup,
      token: token,
      revision: cloud.revision,
      state: payload,
    );
    await DocumentRevisionStore.write('appSettings', account, uploaded.revision);
  } on DioException catch (error) {
    if (error.response?.statusCode != 409) return;
    final again =
        await api.documentBackup(Endpoints.appSettingsBackup, token: token);
    if (again.state != null) {
      final Object? ls = again.state!['learningSettings'];
      if (ls is Map && ls.isNotEmpty) {
        await settingsNotifier.applyFromCloud(Map<String, dynamic>.from(ls));
      }
    }
    final uploaded = await api.documentBackup(
      Endpoints.appSettingsBackup,
      token: token,
      revision: again.revision,
      state: <String, dynamic>{
        'version': 1,
        'learningSettings': settingsNotifier.toSyncJson(),
        'wordReviewPrefs':
            (ref.read(wordReviewSettingsProvider) as WordReviewSettings)
                .toJson(),
      },
    );
    await DocumentRevisionStore.write('appSettings', account, uploaded.revision);
  }
}

Future<void> _syncLearningModules(
  dynamic ref,
  AcquireApiClient api,
  Map<String, dynamic> status,
  bool pushLocal,
) async {
  final Object? modulesRaw = status['learningModules'];
  final Map<String, dynamic> modules = modulesRaw is Map
      ? Map<String, dynamic>.from(modulesRaw)
      : <String, dynamic>{};

  for (final String kind in kLearningModuleKinds) {
    await _safe(() async {
      final int remoteRev = (modules[kind] as num?)?.toInt() ?? 0;
      if (!pushLocal && remoteRev == 0) {
        // Still try pull once to hydrate empty module state.
      }
      final Map<String, dynamic> remote = await api.moduleProgress(kind);
      // Module UI owns merge; ensure GET works. Push is handled by module screens.
      if (pushLocal && remote['state'] == null) {
        // Nothing local to push without module notifier access.
      }
      // Touch ensures route is warm; detailed merge stays in module_screen.
      if (remote['revision'] is int) {
        // no-op: presence confirms mount + auth.
      }
    });
  }
}
