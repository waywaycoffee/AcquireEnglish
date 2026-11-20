import 'dart:io';
import 'dart:typed_data';

import 'package:common_learn_english/features/words/data/lilinji_xlsx_parser.dart';
import 'package:common_learn_english/features/words/domain/syllabus_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseLilinjiText reads tab word+gloss and skips header', () {
    final List<SyllabusWord> words = parseLilinjiText('''
单词\t音标\t释义
abandon\t/əˈbændən/\t放弃
ability\t/əˈbɪləti/\t能力
''');
    expect(words.map((SyllabusWord w) => w.word), <String>['abandon', 'ability']);
    expect(words.first.gloss, '放弃');
  });

  test('parseLilinjiXlsx reads inlineStr sheet sample', () {
    final File file = File(
      'test/fixtures/lilinji_zhongkao_sample.xlsx',
    );
    expect(file.existsSync(), isTrue);
    final List<SyllabusWord> words = parseLilinjiXlsx(
      Uint8List.fromList(file.readAsBytesSync()),
    );
    expect(words.length, greaterThan(100));
    expect(words.any((SyllabusWord w) => w.word == 'ability'), isTrue);
    final SyllabusWord ability = words.firstWhere(
      (SyllabusWord w) => w.word == 'ability',
    );
    expect(ability.gloss, contains('能力'));
  });
}
