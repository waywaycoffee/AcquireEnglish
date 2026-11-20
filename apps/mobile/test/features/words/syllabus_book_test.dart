import 'package:common_learn_english/features/words/domain/syllabus_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSyllabusImport', () {
    test('parses one word per line and skips blanks/comments', () {
      final List<SyllabusWord> words = parseSyllabusImport('''
# header
apple
banana

cherry
''');
      expect(
        words.map((SyllabusWord w) => w.word).toList(),
        <String>['apple', 'banana', 'cherry'],
      );
    });

    test('parses word,gloss and tab-separated gloss', () {
      final List<SyllabusWord> words = parseSyllabusImport('''
abandon,放弃
ability\t能力
''');
      expect(words, hasLength(2));
      expect(words[0].word, 'abandon');
      expect(words[0].gloss, '放弃');
      expect(words[1].word, 'ability');
      expect(words[1].gloss, '能力');
    });

    test('dedupes and strips non-letters', () {
      final List<SyllabusWord> words = parseSyllabusImport('''
Apple!
apple
a
ok
''');
      expect(
        words.map((SyllabusWord w) => w.word).toList(),
        <String>['apple', 'ok'],
      );
    });
  });

  group('syllabusReviewKey', () {
    test('normalizes book and word', () {
      expect(
        syllabusReviewKey('cet4_core', ' Apple '),
        'syllabus:cet4_core:apple',
      );
    });
  });

  group('SyllabusBook.fromJson', () {
    test('reads words as maps or strings', () {
      final SyllabusBook book = SyllabusBook.fromJson(<String, dynamic>{
        'id': 'cet4_core',
        'title': '四级核心',
        'examTag': 'CET4',
        'disclaimer': '自建',
        'words': <Object>[
          <String, String>{'word': 'able', 'gloss': '能够'},
          'about',
        ],
      });
      expect(book.id, 'cet4_core');
      expect(book.wordCount, 2);
      expect(book.words.first.gloss, '能够');
      expect(book.words.last.word, 'about');
      expect(book.kind, SyllabusBookKind.word);
    });

    test('reads pattern book kind', () {
      final SyllabusBook book = SyllabusBook.fromJson(<String, dynamic>{
        'id': 'daily_patterns',
        'title': '日常口语句型',
        'examTag': 'PATTERN',
        'kind': 'pattern',
        'words': <Object>[
          <String, String>{'word': "i'd like to", 'gloss': '我想要'},
        ],
      });
      expect(book.isPatternBook, isTrue);
      expect(book.words.first.word, "i'd like to");
    });
  });

  group('parseSyllabusImport phrases', () {
    test('keeps multi-word lines when allowPhrases', () {
      final List<SyllabusWord> words = parseSyllabusImport(
        "I'd like to,我想要\nas soon as\t一…就…\n",
        allowPhrases: true,
      );
      expect(words.map((SyllabusWord w) => w.word).toList(), <String>[
        "i'd like to",
        'as soon as',
      ]);
      expect(words.first.gloss, '我想要');
    });
  });

  group('deck filter keys', () {
    test('book prefix matches syllabus keys', () {
      const String bookId = 'cet4_core';
      const String key = 'syllabus:cet4_core:abandon';
      expect(key.startsWith('syllabus:'), isTrue);
      expect(key.startsWith('syllabus:$bookId:'), isTrue);
      expect(key.startsWith('syllabus:cet6_core:'), isFalse);
    });
  });
}
