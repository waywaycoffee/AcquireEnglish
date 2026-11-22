from app.services import reading_tts_queue as rtq


def test_split_reading_pages_respects_max_chars():
    text = ("Hello world. " * 200) + "\n\nChapter 2\n\n" + ("More words. " * 200)
    pages = rtq.split_reading_pages(text, max_chars=1800)
    assert len(pages) >= 2
    assert all(len(p) <= 2200 for p in pages)


def test_split_reading_pages_hard_cuts_long_block_without_headings():
    # Wizard-of-Oz-style: one huge block, few chapter markers → must page-cut.
    text = ("Dorothy lived in the midst of the great Kansas prairies. " * 2000)
    pages = rtq.split_reading_pages(text, max_chars=1800)
    assert len(pages) >= 40
    assert all(len(p) <= 2200 for p in pages)


def test_is_long_novel_threshold():
    short = " ".join(["word"] * 100)
    long = " ".join(["word"] * 13000)
    assert not rtq.is_long_novel(short)
    assert rtq.is_long_novel(long)
