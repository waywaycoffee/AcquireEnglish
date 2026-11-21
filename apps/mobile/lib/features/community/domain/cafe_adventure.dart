/// Street-cafe chapter shared by map, feed deep-links, and desk hero.
class CafeLevel {
  const CafeLevel({
    required this.title,
    required this.prompt,
    required this.answers,
    required this.correct,
    required this.explanation,
    required this.ability,
  });

  final String title;
  final String prompt;
  final List<String> answers;
  final int correct;
  final String explanation;
  final String ability;
}

const String kCafeChapterPath = '/community/explore/cafe';
const int kCafeWeeklyTarget = 3;

const List<CafeLevel> kCafeLevels = <CafeLevel>[
  CafeLevel(
    title: '看懂菜单',
    prompt:
        '菜单：Small coffee £2 · Large coffee £3 · Small tea £2。\n你有 £2，想喝咖啡。选哪一款？',
    answers: <String>['Large coffee', 'Small coffee', 'Small tea'],
    correct: 1,
    explanation: 'Small coffee 同时满足饮品和预算要求。',
    ability: '读懂价目与预算',
  ),
  CafeLevel(
    title: '开口点单',
    prompt: '店员问 “What can I get for you?” 你想点一杯小杯咖啡外带。',
    answers: <String>[
      'A small coffee to go, please.',
      'A large coffee to go, please.',
      'A small coffee for here, please.',
    ],
    correct: 0,
    explanation: 'To go 表示外带。选好后可以把整句话读一遍。',
    ability: '点单 + 外带',
  ),
  CafeLevel(
    title: '修改订单',
    prompt: '你已经点了咖啡，想把牛奶换成燕麦奶。怎么说？',
    answers: <String>[
      'Could I get another coffee?',
      'Could I have it without milk?',
      'Could I get that with oat milk instead?',
    ],
    correct: 2,
    explanation: 'With oat milk instead 表示改用燕麦奶。',
    ability: '改规格 / 替换配料',
  ),
  CafeLevel(
    title: '售罄挑战',
    prompt: '店员说 “Sorry, we’re out of coffee.” 你想改成小杯茶，并确认外带。',
    answers: <String>[
      'I’ll have a small tea to go, then.',
      'I’ll wait for the coffee.',
      'A small tea for here, please.',
    ],
    correct: 0,
    explanation: 'Then 在这里表示「那就」，to go 确认外带。',
    ability: '应变换单',
  ),
];

String cafeChallengePath(int levelIndex) =>
    '$kCafeChapterPath/${levelIndex + 1}';

int? cafeLevelFromPath(String? path) {
  final String raw = (path ?? '').trim();
  for (int index = 0; index < kCafeLevels.length; index++) {
    if (raw == cafeChallengePath(index)) return index;
  }
  return null;
}

/// ISO-like week id in local time: `2026-W47`.
String cafeWeekId([DateTime? now]) {
  final DateTime d = (now ?? DateTime.now()).toLocal();
  // Thursday-based ISO week number.
  final DateTime utc = DateTime.utc(d.year, d.month, d.day);
  final int dayOfWeek = utc.weekday; // Mon=1 … Sun=7
  final DateTime thursday = utc.add(Duration(days: 4 - dayOfWeek));
  final DateTime jan4 = DateTime.utc(thursday.year, 1, 4);
  final int week =
      1 + ((thursday.difference(jan4).inDays + jan4.weekday - 1) ~/ 7);
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}
