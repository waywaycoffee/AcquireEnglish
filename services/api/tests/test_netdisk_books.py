from app.services.netdisk_books import choose_book_formats


def test_choose_book_formats_prefers_epub_per_title_variant():
    paths = [
        "/drive/Pride and Prejudice.mobi",
        "/drive/Pride and Prejudice.epub",
        "/drive/Pride and Prejudice 中文版.pdf",
        "/drive/notes.txt",
    ]
    books = choose_book_formats(paths)
    by_title_variant = {(row["title"], row["variant"]): row for row in books}
    assert by_title_variant[("Pride and Prejudice", "未标注版本")]["format"] == "epub"
    assert by_title_variant[("Pride and Prejudice 中文版", "中文")]["format"] == "pdf"
    assert by_title_variant[("notes", "未标注版本")]["format"] == "txt"
    assert len(books) == 3


def test_choose_book_formats_epub_only():
    paths = [
        "/drive/Animal Farm.pdf",
        "/drive/Animal Farm.epub",
    ]
    books = choose_book_formats(paths, epub_only=True)
    assert books == [
        {
            "title": "Animal Farm",
            "variant": "未标注版本",
            "format": "epub",
            "path": "/drive/Animal Farm.epub",
        }
    ]
