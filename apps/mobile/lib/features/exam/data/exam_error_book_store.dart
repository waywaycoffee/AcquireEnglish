import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../sync/data/schedule_device_cloud_sync.dart';

const String kExamErrorBookKey = 'exam_error_book_v1';

class ExamErrorItem {
  const ExamErrorItem({
    required this.id,
    required this.familyId,
    required this.skill,
    required this.prompt,
    required this.wrongAnswer,
    required this.correctAnswer,
    required this.createdAtMs,
    this.note = '',
    this.addedToFsrs = false,
  });

  factory ExamErrorItem.fromJson(Map<String, dynamic> json) => ExamErrorItem(
        id: '${json['id'] ?? ''}',
        familyId: '${json['familyId'] ?? ''}',
        skill: '${json['skill'] ?? 'practice'}',
        prompt: '${json['prompt'] ?? ''}',
        wrongAnswer: '${json['wrongAnswer'] ?? ''}',
        correctAnswer: '${json['correctAnswer'] ?? ''}',
        note: '${json['note'] ?? ''}',
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
        addedToFsrs: json['addedToFsrs'] == true,
      );

  final String id;
  final String familyId;
  final String skill;
  final String prompt;
  final String wrongAnswer;
  final String correctAnswer;
  final String note;
  final int createdAtMs;
  final bool addedToFsrs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'familyId': familyId,
        'skill': skill,
        'prompt': prompt,
        'wrongAnswer': wrongAnswer,
        'correctAnswer': correctAnswer,
        'note': note,
        'createdAtMs': createdAtMs,
        'addedToFsrs': addedToFsrs,
      };

  ExamErrorItem copyWith({bool? addedToFsrs}) => ExamErrorItem(
        id: id,
        familyId: familyId,
        skill: skill,
        prompt: prompt,
        wrongAnswer: wrongAnswer,
        correctAnswer: correctAnswer,
        note: note,
        createdAtMs: createdAtMs,
        addedToFsrs: addedToFsrs ?? this.addedToFsrs,
      );
}

class ExamErrorBookNotifier extends Notifier<List<ExamErrorItem>> {
  @override
  List<ExamErrorItem> build() => _load();

  List<ExamErrorItem> _load() {
    if (!Hive.isBoxOpen('prefs')) return const <ExamErrorItem>[];
    final String? raw = Hive.box<String>('prefs').get(kExamErrorBookKey);
    if (raw == null || raw.isEmpty) return const <ExamErrorItem>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map(
            (Map e) => ExamErrorItem.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false);
    } catch (_) {
      return const <ExamErrorItem>[];
    }
  }

  Future<void> _persist(List<ExamErrorItem> next) async {
    state = List<ExamErrorItem>.unmodifiable(next);
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
          kExamErrorBookKey,
          jsonEncode(next.map((ExamErrorItem e) => e.toJson()).toList()),
        );
    scheduleDeviceCloudSync(key: 'settings');
  }

  Future<void> add(ExamErrorItem item) async {
    final List<ExamErrorItem> next = <ExamErrorItem>[item, ...state];
    await _persist(next.take(500).toList(growable: false));
  }

  Future<void> markFsrs(String id) async {
    final List<ExamErrorItem> next = state
        .map(
          (ExamErrorItem e) => e.id == id ? e.copyWith(addedToFsrs: true) : e,
        )
        .toList(growable: false);
    await _persist(next);
  }

  Future<void> remove(String id) async {
    await _persist(
      state.where((ExamErrorItem e) => e.id != id).toList(growable: false),
    );
  }

  Future<void> replaceFromCloud(List<ExamErrorItem> items) async {
    await _persist(items.take(500).toList(growable: false));
  }

  List<ExamErrorItem> forFamily(String? familyId) {
    if (familyId == null || familyId.isEmpty) return state;
    return state
        .where((ExamErrorItem e) => e.familyId == familyId || e.familyId.isEmpty)
        .toList(growable: false);
  }
}

final NotifierProvider<ExamErrorBookNotifier, List<ExamErrorItem>>
    examErrorBookProvider =
    NotifierProvider<ExamErrorBookNotifier, List<ExamErrorItem>>(
  ExamErrorBookNotifier.new,
);
