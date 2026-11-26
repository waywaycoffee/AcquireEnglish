import 'package:common_learn_english/features/words/domain/syllabus_book.dart';
import 'package:common_learn_english/features/words/domain/syllabus_book_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyllabusBookCategory.tabs', () {
    test('exactly 8 tabs in required order', () {
      expect(
        SyllabusBookCategory.tabs.map((e) => e.label).toList(),
        const <String>[
          '句型',
          '拼读',
          '小学',
          '初中',
          '高中',
          '大学',
          '出国',
          '职业',
        ],
      );
    });
  });

  group('classifySyllabusBookCategory', () {
    test('pattern kind → 句型', () {
      expect(
        classifySyllabusBookCategory(
          title: '日常口语句型',
          examTag: 'PATTERN',
          kind: SyllabusBookKind.pattern,
        ),
        SyllabusBookCategory.pattern,
      );
      expect(
        classifySyllabusBookCategory(
          title: '程序员口语句型',
          examTag: 'SPEAK',
          kind: SyllabusBookKind.pattern,
        ),
        SyllabusBookCategory.pattern,
      );
    });

    test('句型 keywords match before career / school buckets', () {
      expect(
        classifySyllabusBookCategory(title: '日常口语句型'),
        SyllabusBookCategory.pattern,
      );
      expect(
        classifySyllabusBookCategory(title: '情景句 151'),
        SyllabusBookCategory.pattern,
      );
      expect(
        classifySyllabusBookCategory(title: '常用句式'),
        SyllabusBookCategory.pattern,
      );
      expect(
        classifySyllabusBookCategory(title: 'Sentence Patterns A1'),
        SyllabusBookCategory.pattern,
      );
      expect(
        classifySyllabusBookCategory(title: 'Useful Phrases'),
        SyllabusBookCategory.pattern,
      );
      expect(
        classifySyllabusBookCategory(title: '程序员口语句型'),
        SyllabusBookCategory.pattern,
      );
      expect(
        classifySyllabusBookCategory(title: '语块训练'),
        SyllabusBookCategory.pattern,
      );
    });

    test('foundation kind → 拼读', () {
      expect(
        classifySyllabusBookCategory(
          title: '国际音标 48 音素',
          examTag: 'IPA48',
          kind: SyllabusBookKind.foundation,
        ),
        SyllabusBookCategory.phonics,
      );
      expect(
        classifySyllabusBookCategory(
          title: '自然拼读 · 100+ 规则',
          examTag: 'RULES',
          kind: SyllabusBookKind.foundation,
        ),
        SyllabusBookCategory.phonics,
      );
    });

    test('school levels by examTag / title', () {
      expect(
        classifySyllabusBookCategory(title: '小学适配·三年级起', examTag: 'PEP3'),
        SyllabusBookCategory.primary,
      );
      expect(
        classifySyllabusBookCategory(title: '初中核心', examTag: 'JH'),
        SyllabusBookCategory.junior,
      );
      expect(
        classifySyllabusBookCategory(title: '高考核心', examTag: 'GK'),
        SyllabusBookCategory.senior,
      );
      expect(
        classifySyllabusBookCategory(title: '高中核心', examTag: 'SH'),
        SyllabusBookCategory.senior,
      );
      expect(
        classifySyllabusBookCategory(title: '义务教育课标适配', examTag: 'K12'),
        SyllabusBookCategory.primary,
      );
    });

    test('college / abroad / career', () {
      expect(
        classifySyllabusBookCategory(title: '四级核心', examTag: 'CET4'),
        SyllabusBookCategory.college,
      );
      expect(
        classifySyllabusBookCategory(title: '考研核心', examTag: 'KY'),
        SyllabusBookCategory.college,
      );
      expect(
        classifySyllabusBookCategory(title: '常用 3000 词', examTag: 'HF3K'),
        SyllabusBookCategory.college,
      );
      expect(
        classifySyllabusBookCategory(title: '雅思核心', examTag: 'IELTS'),
        SyllabusBookCategory.abroad,
      );
      expect(
        classifySyllabusBookCategory(title: '托福核心', examTag: 'TOEFL'),
        SyllabusBookCategory.abroad,
      );
      expect(
        classifySyllabusBookCategory(
          title: '商务英语',
          examTag: 'BEC',
          path: '8.商务英语',
        ),
        SyllabusBookCategory.career,
      );
      expect(
        classifySyllabusBookCategory(
          title: 'IT / 开发英语',
          examTag: 'IT',
          path: '9.扇贝英语（IT）',
        ),
        SyllabusBookCategory.career,
      );
    });

    test('lilinji open-source category tags', () {
      expect(
        classifySyllabusBookCategory(
          title: '中考',
          examTag: 'ZK',
          path: '2.中考',
        ),
        SyllabusBookCategory.junior,
      );
      expect(
        classifySyllabusBookCategory(
          title: '雅思 IELTS',
          examTag: 'IELTS',
          path: '7.雅思',
        ),
        SyllabusBookCategory.abroad,
      );
      expect(
        classifySyllabusBookCategory(
          title: '其他（GRE/SAT/GMAT 等）',
          examTag: 'OTHER',
          path: '9.其他（更多）',
        ),
        SyllabusBookCategory.abroad,
      );
    });

    test('unknown title soft-falls back to 大学', () {
      expect(
        classifySyllabusBookCategory(title: 'Mystery Word Pack', examTag: ''),
        SyllabusBookCategory.college,
      );
    });
  });
}
