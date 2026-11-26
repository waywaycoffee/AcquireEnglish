import unittest
from pathlib import Path

from scan_local import _match_edition, _pick_pdf, scan_local_tree


class ScanLocalTest(unittest.TestCase):
    def test_hot_edition_matching(self) -> None:
        key, label, publisher, score, hot = _match_edition(
            "人教版（PEP）（主编：吴欣）"
        )
        self.assertTrue(hot)
        self.assertEqual(key, "pep-y3-wuxin")
        self.assertGreaterEqual(score, 90)

        key, label, publisher, score, hot = _match_edition("北京版")
        self.assertTrue(hot)
        self.assertEqual(key, "beijing")

        key, label, publisher, score, hot = _match_edition("川教版")
        self.assertFalse(hot)

    def test_scan_sample_tree(self) -> None:
        root = Path(__file__).resolve().parents[2] / "docs" / "教材"
        if not root.is_dir():
            self.skipTest("local 教材 tree missing")
        rows = scan_local_tree(root, hot_only=True, min_mp3=5)
        self.assertTrue(any(r.book_id == "beijing-g4-b" for r in rows))
        beijing = next(r for r in rows if r.book_id == "beijing-g4-b")
        self.assertTrue(beijing.ready)
        self.assertEqual(beijing.mp3_count, 37)
        self.assertTrue(beijing.pdf_name.endswith(".pdf"))


if __name__ == "__main__":
    unittest.main()
