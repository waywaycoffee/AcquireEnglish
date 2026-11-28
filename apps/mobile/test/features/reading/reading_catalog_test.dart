import 'package:common_learn_english/features/reading/data/reading_catalog.dart';
import 'package:common_learn_english/features/reading/data/reading_open_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default long-form book is the Standard Ebooks Wizard of Oz', () {
    expect(kDefaultWizardOfOzEntry.title, 'The Wonderful Wizard of Oz');
    expect(
      kDefaultWizardOfOzEntry.path,
      'l-frank-baum/the-wonderful-wizard-of-oz',
    );
    expect(kDefaultWizardOfOzEntry.kind, ReadingCatalogEntryKind.ebook);
    expect(kDefaultWizardOfOzEntry.stableDocId, startsWith('catalog_'));
    expect(
      kStandardEbooksFeatured.any(
        (book) => book.path == kDefaultWizardOfOzEntry.path,
      ),
      isTrue,
    );
  });

  group('parseCefrLeveledCsv', () {
    test('reads text and label columns', () {
      const String csv = '''
text,label
"Hello world. This is a short A1 text.",A1
"Another story for B1 learners with more words.",B1
''';
      final List<ReadingCatalogEntry> entries = parseCefrLeveledCsv(csv);
      expect(entries, hasLength(2));
      expect(entries.first.level, 'A1');
      expect(entries.last.level, 'B1');
      expect(entries.first.id, startsWith('cefr_a1_'));
    });
  });

  group('parseMagicStoriesIndex', () {
    test('extracts id title and paragraph texts', () {
      const String raw = r'''
export const l1Stories = [
  {
    id: 'l1_001',
    level: 1,
    title: 'The Magic Apple',
    titleCn: '魔法苹果',
    content: [
      {
        paragraphId: 'p1',
        text: 'Once upon a time, there was a red apple.',
        translation: '从前',
        words: [
          { word: 'Once', start: 0, end: 400, index: 0 },
          { word: 'upon', start: 400, end: 700, index: 1 },
        ],
      },
      {
        paragraphId: 'p2',
        text: 'It was sweet.',
        translation: '它很甜',
        words: [{ word: 'It', start: 0, end: 100, index: 0 }],
      },
    ],
  },
  {
    id: 'l1_001_q1',
    type: 'image_choice',
    question: 'What color?',
    options: [
      { text: 'Red' },
    ],
  },
  {
    id: 'l1_002',
    level: 1,
    title: 'A Little Cat',
    titleCn: '小猫',
    content: [
      {
        paragraphId: 'p1',
        text: 'I have a little cat.',
        words: [{ word: 'I', start: 0, end: 1, index: 0 }],
      },
    ],
  },
];
''';
      final List<ReadingCatalogEntry> stories = parseMagicStoriesIndex(
        raw,
        path: 'src/data/stories/l1/index.ts',
      );
      expect(stories, hasLength(2));
      expect(stories.first.title, 'The Magic Apple');
      expect(stories.first.level, 'L1');
      expect(stories.first.subtitle, contains('red apple'));
      expect(stories.first.subtitle, contains('sweet'));
      expect(stories.last.id, 'magic:l1_002');
      expect(stories.last.subtitle, contains('little cat'));
    });
  });

  group('open reading sources', () {
    test(
      'parses a Standard Ebooks browse page without treating per-page as a page number',
      () {
        const String html = '''
<ol>
<li typeof="schema:Book" about="/ebooks/jane-austen/pride-and-prejudice">
<span property="schema:name">Pride and Prejudice</span>
<p class="author"><span property="schema:name">Jane Austen</span></p>
</li>
<li typeof="schema:Book" about="/ebooks/l-frank-baum/the-wonderful-wizard-of-oz">
<span property="schema:name">The Wonderful Wizard of Oz</span>
<p class="author"><span property="schema:name">L. Frank Baum</span></p>
</li>
</ol>
<a href="/ebooks?per-page=48&amp;page=2">2</a>
<a href="/ebooks?per-page=48&amp;page=3">3</a>
''';
        final StandardEbooksBrowse page = parseStandardEbooksBrowsePage(html);
        expect(page.lastPage, 3);
        expect(page.books, hasLength(2));
        expect(page.books.first.path, 'jane-austen/pride-and-prejudice');
        expect(page.books.first.author, 'Jane Austen');
      },
    );

    test('lists Book Dash English texts and skips empty placeholders', () {
      const String raw = '''
{"tree":[
 {"path":"sleepy-mr-sloth/en/index.md","type":"blob","size":2100},
 {"path":"i-can-dress-myself/en/index.md","type":"blob","size":462},
 {"path":"images/cover.jpg","type":"blob","size":9000},
 {"path":"a-house-for-mouse/en/index.md","type":"blob","size":1600}
]}
''';
      final List<BookDashRef> books = parseBookDashTree(raw);
      expect(books.map((BookDashRef b) => b.slug), [
        'a-house-for-mouse',
        'sleepy-mr-sloth',
      ]);
      expect(books.first.title, 'A House for Mouse');
      expect(bookDashTitleFromSlug('sleepy-mr-sloth'), 'Sleepy Mr Sloth');
    });

    test('reads Book Dash markdown and creator credits', () {
      const String md = '''
---
title: Sleepy Mr Sloth
---

# Sleepy Mr Sloth

![Mr Sloth is sleepy.]({{ site.image-set }}/01.jpg)

One day, Mr Sloth came to visit.

I’m sleepy! I need a good branch for a bed!
''';
      final BookDashText story = parseBookDashMarkdown(md);
      expect(story.title, 'Sleepy Mr Sloth');
      expect(story.body, contains('Mr Sloth came to visit'));
      expect(story.body, contains('good branch'));
      expect(story.body, isNot(contains('image-set')));
      const String html = '''
<span class="txt-bold">Paul Kennedy</span> (Writer)
<span class="txt-bold">Nick Mulgrew</span> (Illustrator)
''';
      final Map<String, String> credits = parseBookDashCredits(html);
      expect(credits['writer'], 'Paul Kennedy');
      expect(
        bookDashAttribution(slug: 'sleepy-mr-sloth', credits: credits),
        contains('Paul Kennedy (Writer)'),
      );
      expect(
        bookDashAttribution(slug: 'sleepy-mr-sloth', credits: credits),
        contains('https://bookdash.org/books/sleepy-mr-sloth/'),
      );
    });

    test('parses VOA rss items and keeps the slugged article', () {
      const String xml = '''
<rss><channel>
<item>
<title>&apos;Watching the Grass Grow&apos; Is Not Fun</title>
<link>https://learningenglish.voanews.com/a/watching-the-grass-grow-is-not-fun/8003108.html</link>
<description>Spring is exciting.</description>
</item>
<item>
<title>&#39;Watching the Grass Grow&#39; Is Not Fun</title>
<link>https://learningenglish.voanews.com/a/8006750.html</link>
<description></description>
</item>
<item>
<title>Wire copy</title>
<link>https://www.voanews.com/a/not-learning/1.html</link>
<description>skip</description>
</item>
</channel></rss>
''';
      final List<VoaFeedItem> items = parseVoaRss(xml);
      expect(items, hasLength(1));
      expect(items.single.id, '8003108');
      expect(items.single.title, "'Watching the Grass Grow' Is Not Fun");
      expect(items.single.summary, 'Spring is exciting.');
    });

    test('extracts a VOA Learning English article and flags wire copy', () {
      const String html = '''
<title>&#x27;Watching the Grass Grow&#x27; Is Not Fun</title>
<script>byline:"not set"</script>
<div class="wsw">
<p>No media source currently available</p>
<p>And now Words and Their Stories from VOA Learning English.</p>
<p>Springtime is a time of renewal and growth.</p>
<h2>Words in This Story</h2>
<p><strong>bud</strong> <em>–n.</em> the beginnings of a flower</p>
</div>
<div class="footer-toolbar">share</div>
''';
      final VoaArticle article = parseVoaArticle(html);
      expect(article.wireService, isFalse);
      expect(article.title, contains('Watching the Grass Grow'));
      expect(article.text, contains('Springtime is a time of renewal'));
      expect(article.text, contains('Words in This Story'));
      expect(article.text, isNot(contains('No media source')));
      expect(article.text, contains('bud'));
      expect(
        parseVoaArticle(
          '<script>byline:"Associated Press"</script>',
        ).wireService,
        isTrue,
      );
    });
  });
}
