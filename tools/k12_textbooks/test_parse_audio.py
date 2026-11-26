import unittest
from pathlib import Path

from parse_audio import parse_audio_filename, scan_audio_folder


class ParseAudioTest(unittest.TestCase):
    def test_lesson_and_letters(self) -> None:
        lesson = parse_audio_filename(
            "01_Unit One_Lesson 1  What's Your Hobby.mp3"
        )
        assert lesson is not None
        self.assertEqual(lesson.seq, 1)
        self.assertEqual(lesson.unit, 1)
        self.assertEqual(lesson.lesson, 1)
        self.assertEqual(lesson.kind, "lesson")
        self.assertEqual(lesson.title, "What's Your Hobby")

        letters = parse_audio_filename(
            "05_Unit One_Letters and Sounds\u2003sh.mp3"
        )
        assert letters is not None
        self.assertEqual(letters.unit, 1)
        self.assertEqual(letters.kind, "letters")
        self.assertEqual(letters.title, "sh")

    def test_wordlist_and_reading(self) -> None:
        wordlist = parse_audio_filename("36_word List_Word List (1）.mp3")
        assert wordlist is not None
        self.assertEqual(wordlist.kind, "wordlist")
        reading = parse_audio_filename(
            "35_Reading for Pleasure_Reading for Pleasure.mp3"
        )
        assert reading is not None
        self.assertEqual(reading.kind, "reading")

    def test_sample_folder(self) -> None:
        folder = (
            Path(__file__).resolve().parents[2]
            / "docs"
            / "教材"
            / "小学"
            / "英语"
            / "北京版"
            / "四年级"
            / "下册"
        )
        if not folder.is_dir():
            self.skipTest("sample folder not present")
        tracks = scan_audio_folder(folder)
        self.assertEqual(len(tracks), 37)
        self.assertEqual(tracks[0].title, "What's Your Hobby")
        self.assertEqual(tracks[4].kind, "letters")


if __name__ == "__main__":
    unittest.main()
