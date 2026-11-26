import 'dart:typed_data';

import 'package:common_learn_english/features/reading/data/reading_netdisk_import.dart';
import 'package:common_learn_english/features/reading/data/reading_vocab_lists.dart';
import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:common_learn_english/features/sync/data/reading_library_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const NetdiskEpubRef oz = NetdiskEpubRef(
    path: '/baidu/books/wizard.epub',
    title: 'The Wonderful Wizard of Oz',
    variant: '英版',
  );

  ReadingDoc doc({
    required String id,
    required String title,
    String text = 'Once upon a time.',
    String sourceLabel = '',
    String netdiskPath = '',
  }) => ReadingDoc(
    id: id,
    title: title,
    sourceType: ReadingSourceType.import,
    plainText: text,
    sourceLabel: sourceLabel,
    netdiskPath: netdiskPath,
  );

  test('same file keeps one id after trailing-slash cleanup', () {
    expect(
      netdiskReadingDocId('/baidu/books/wizard.epub'),
      netdiskReadingDocId('/baidu/books/wizard.epub/'),
    );
  });

  test('skips a book already stored by path, id, or legacy title', () {
    final String id = netdiskReadingDocId(oz.path);
    expect(
      isNetdiskBookImported(oz, <ReadingDoc>[doc(id: id, title: 'other')]),
      isTrue,
    );
    expect(
      isNetdiskBookImported(oz, <ReadingDoc>[
        doc(id: 'old', title: 'x', netdiskPath: oz.path),
      ]),
      isTrue,
    );
    expect(
      isNetdiskBookImported(oz, <ReadingDoc>[
        doc(
          id: 'legacy',
          title: 'The Wonderful Wizard of Oz（绿野仙踪）',
          sourceLabel: '百度网盘 · 英版',
        ),
      ]),
      isTrue,
    );
    expect(
      isNetdiskBookImported(oz, <ReadingDoc>[
        doc(
          id: 'other-edition',
          title: 'The Wonderful Wizard of Oz',
          sourceLabel: '百度网盘 · 中文',
        ),
      ]),
      isFalse,
    );
  });

  test(
    'imports only books missing from the shelf and stops at the quota',
    () async {
      final List<String> downloaded = <String>[];
      final List<ReadingDoc> saved = <ReadingDoc>[];
      final NetdiskImportOutcome outcome = await importPendingNetdiskEpubs(
        books: const <NetdiskEpubRef>[
          oz,
          NetdiskEpubRef(path: '/baidu/books/new.epub', title: 'New Book'),
          NetdiskEpubRef(path: '/baidu/books/later.epub', title: 'Later'),
        ],
        existing: <ReadingDoc>[
          doc(id: netdiskReadingDocId(oz.path), title: oz.title),
        ],
        importCount: 1,
        maxImportDocs: 2,
        download: (String path) async {
          downloaded.add(path);
          return Uint8List.fromList(<int>[1]);
        },
        parse: (Uint8List bytes, String path) async => 'Chapter from $path',
        save: (ReadingDoc book) async {
          saved.add(book);
          return book;
        },
      );

      expect(downloaded, <String>['/baidu/books/new.epub']);
      expect(saved.single.netdiskPath, '/baidu/books/new.epub');
      expect(outcome.imported, 1);
      expect(outcome.skipped, 1);
      expect(outcome.hitQuota, isTrue);
      expect(saved.single.id, netdiskReadingDocId('/baidu/books/new.epub'));
    },
  );

  test('a failed book does not stop the rest of the folder', () async {
    final NetdiskImportOutcome outcome = await importPendingNetdiskEpubs(
      books: const <NetdiskEpubRef>[
        NetdiskEpubRef(path: '/baidu/bad.epub', title: 'Bad'),
        NetdiskEpubRef(path: '/baidu/good.epub', title: 'Good'),
      ],
      existing: const <ReadingDoc>[],
      importCount: 0,
      maxImportDocs: 50,
      download: (String path) async {
        if (path.endsWith('bad.epub')) throw StateError('网盘文件不可读取');
        return Uint8List.fromList(<int>[1]);
      },
      parse: (Uint8List bytes, String path) async => 'Readable text',
      save: (ReadingDoc book) async => book,
    );

    expect(outcome.imported, 1);
    expect(outcome.failed, 1);
    expect(outcome.errors.single, contains('Bad'));
    expect(summarizeNetdiskImport(outcome), contains('新导入 1 本'));
  });

  test('shelf config round-trips and dedupes folders', () {
    final ReadingNetdiskShelfConfig config = ReadingNetdiskShelfConfig.fromJson(
      <String, dynamic>{
        'autoImport': false,
        'folders': <String>['/baidu/books/', '/baidu/books', ''],
        'lastSummary': '百度网盘书架已是最新',
        'lastFailed': true,
      },
    );
    final ReadingNetdiskShelfConfig again = ReadingNetdiskShelfConfig.fromJson(
      config.toJson(),
    );

    expect(again.autoImport, isFalse);
    expect(again.folders, <String>['/baidu/books']);
    expect(again.lastSummary, '百度网盘书架已是最新');
    expect(again.lastFailed, isTrue);
    expect(again.isWatching('/baidu/books/'), isTrue);
  });

  test(
    'cloud merge keeps the netdisk path when the richer copy omitted it',
    () {
      final ReadingDoc local = doc(
        id: 'netdisk_abc',
        title: 'Oz',
        text: 'short',
        netdiskPath: '/baidu/books/wizard.epub',
      );
      final ReadingDoc remote = doc(
        id: 'netdisk_abc',
        title: 'Oz',
        text: 'a longer body from another device',
      );
      final ReadingLibrarySnapshot merged = mergeReadingLibraries(
        ReadingLibrarySnapshot(
          docs: <ReadingDoc>[local],
          progress: const <String, ReadingProgress>{},
          vocabLists: const ReadingVocabLists(),
        ),
        ReadingLibrarySnapshot(
          docs: <ReadingDoc>[remote],
          progress: const <String, ReadingProgress>{},
          vocabLists: const ReadingVocabLists(),
        ),
      );

      expect(merged.docs.single.plainText, remote.plainText);
      expect(merged.docs.single.netdiskPath, '/baidu/books/wizard.epub');
    },
  );
}
