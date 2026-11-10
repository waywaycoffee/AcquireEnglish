import 'package:common_learn_english/features/import_course/domain/bilibili_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BilibiliImport.extractIds', () {
    test('parses full BV url', () {
      expect(
        BilibiliImport.extractIds(
          'https://www.bilibili.com/video/BV1xx411c7mD',
        ),
        <String, String>{'bvid': 'BV1xx411c7mD'},
      );
    });

    test('parses BV inside share text with full url', () {
      expect(
        BilibiliImport.extractIds(
          '【标题-哔哩哔哩】 https://www.bilibili.com/video/BV1xx411c7mD/?spm_id_from=333',
        ),
        <String, String>{'bvid': 'BV1xx411c7mD'},
      );
    });

    test('parses bare BV / av', () {
      expect(BilibiliImport.extractIds('BV1xx411c7mD'), <String, String>{
        'bvid': 'BV1xx411c7mD',
      });
      expect(BilibiliImport.extractIds('av170001'), <String, String>{
        'aid': '170001',
      });
    });
  });

  group('BilibiliImport share / short link detection', () {
    const String shareText =
        '【用可理解输入神技秒杀3000核心词汇！无痛记忆，真正印在脑子里-哔哩哔哩】 https://b23.tv/fnJy3OH';

    test('accepts phone share paste with b23.tv', () {
      expect(BilibiliImport.looksLikeBilibiliInput(shareText), isTrue);
      expect(BilibiliImport.isShortLink(shareText), isTrue);
      expect(
        BilibiliImport.firstUrlInText(shareText),
        'https://b23.tv/fnJy3OH',
      );
      expect(
        BilibiliImport.normalizeInput(shareText),
        'https://b23.tv/fnJy3OH',
      );
    });

    test('sanitizes zero-width and NBSP in share paste', () {
      const String dirty =
          '【标题-哔哩哔哩】\u00a0https://b23.tv/fnJy3OH\u200b';
      expect(BilibiliImport.looksLikeBilibiliInput(dirty), isTrue);
      expect(
        BilibiliImport.normalizeInput(dirty),
        'https://b23.tv/fnJy3OH',
      );
    });

    test('builds short-link host fallbacks from code', () {
      expect(BilibiliImport.shortLinkCode(shareText), 'fnJy3OH');
      expect(
        BilibiliImport.shortLinkCandidates(shareText).first,
        'https://bili2233.cn/fnJy3OH',
      );
      expect(
        BilibiliImport.shortLinkCandidates(shareText),
        contains('https://b23.tv/fnJy3OH'),
      );
    });

    test('accepts bare short link without scheme', () {
      expect(BilibiliImport.looksLikeBilibiliInput('b23.tv/fnJy3OH'), isTrue);
      expect(
        BilibiliImport.firstUrlInText('b23.tv/fnJy3OH'),
        'https://b23.tv/fnJy3OH',
      );
    });

    test('rejects unrelated text', () {
      expect(BilibiliImport.looksLikeBilibiliInput('hello world'), isFalse);
      expect(BilibiliImport.extractIds(shareText), isNull);
    });
  });
}
