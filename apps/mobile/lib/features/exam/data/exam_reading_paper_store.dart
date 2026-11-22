import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../sync/data/schedule_device_cloud_sync.dart';
import '../domain/exam_reading_paper.dart';

const String kExamRcPapersKey = 'exam_rc_papers_v1';
const String kExamRcSkillDoneKey = 'exam_rc_skill_done_v1';

class ExamReadingPaperState {
  const ExamReadingPaperState({
    this.papers = const <ExamRcPaper>[],
    this.skillDone = false,
  });

  final List<ExamRcPaper> papers;
  final bool skillDone;

  ExamReadingPaperState copyWith({
    List<ExamRcPaper>? papers,
    bool? skillDone,
  }) =>
      ExamReadingPaperState(
        papers: papers ?? this.papers,
        skillDone: skillDone ?? this.skillDone,
      );
}

class ExamReadingPaperNotifier extends Notifier<ExamReadingPaperState> {
  String get _account => ref.watch(studyAccountProvider);

  String get _papersKey => studyStorageKey(kExamRcPapersKey, _account);

  String get _skillKey => studyStorageKey(kExamRcSkillDoneKey, _account);

  @override
  ExamReadingPaperState build() {
    ref.watch(studyAccountProvider);
    return _load();
  }

  ExamReadingPaperState _load() {
    if (!Hive.isBoxOpen('prefs')) {
      return ExamReadingPaperState(papers: <ExamRcPaper>[kExamRcDemoPaper]);
    }
    final Box<String> box = Hive.box<String>('prefs');
    final bool skillDone = box.get(_skillKey) == '1';
    final String? raw = box.get(_papersKey);
    List<ExamRcPaper> papers = <ExamRcPaper>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
        papers = list
            .whereType<Map>()
            .map((Map e) => ExamRcPaper.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: true);
      } catch (_) {}
    }
    if (!papers.any((ExamRcPaper p) => p.id == kExamRcDemoPaper.id)) {
      papers = <ExamRcPaper>[kExamRcDemoPaper, ...papers];
    }
    return ExamReadingPaperState(
      papers: List<ExamRcPaper>.unmodifiable(papers),
      skillDone: skillDone,
    );
  }

  Future<void> _persistPapers(List<ExamRcPaper> papers) async {
    state = state.copyWith(papers: List<ExamRcPaper>.unmodifiable(papers));
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
          _papersKey,
          jsonEncode(papers.map((ExamRcPaper p) => p.toJson()).toList()),
        );
    scheduleDeviceCloudSync(key: 'settings');
  }

  Future<void> markSkillDone() async {
    state = state.copyWith(skillDone: true);
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(_skillKey, '1');
    scheduleDeviceCloudSync(key: 'settings');
  }

  Future<void> upsert(ExamRcPaper paper) async {
    final List<ExamRcPaper> next = <ExamRcPaper>[
      paper,
      ...state.papers.where((ExamRcPaper p) => p.id != paper.id),
    ];
    await _persistPapers(next);
  }

  Future<void> remove(String id) async {
    if (id == kExamRcDemoPaper.id) return;
    await _persistPapers(
      state.papers.where((ExamRcPaper p) => p.id != id).toList(growable: false),
    );
  }

  ExamRcPaper? byId(String id) {
    for (final ExamRcPaper p in state.papers) {
      if (p.id == id) return p;
    }
    if (id == kExamRcDemoPaper.id) return kExamRcDemoPaper;
    return null;
  }
}

final NotifierProvider<ExamReadingPaperNotifier, ExamReadingPaperState>
    examReadingPaperProvider =
    NotifierProvider<ExamReadingPaperNotifier, ExamReadingPaperState>(
  ExamReadingPaperNotifier.new,
);
