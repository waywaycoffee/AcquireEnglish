import unittest
from grades import GRADES
from validator import validate_one

class GradeValidationTest(unittest.TestCase):
    def article(self, grade, count):
        return {'grade_id': grade, 'level': GRADES[grade]['name'],
            'article': {'passage': ' '.join(['word'] * count), 'word_count': count},
            'questions': [{'q_no': i, 'question': 'Why?', 'options': dict.fromkeys('ABCD','option'), 'answer':'A','analysis':'解析'} for i in range(1,5)],
            'word_list': [], 'long_sentences': [{'sentence':'word','translation':'词','grammar_analysis':'分析'} for _ in range(2)],
            'digital_human': {'topic_name':'主题','question_list':['What?','Why?','How?']}}

    def test_all_twelve_grade_boundaries(self):
        self.assertEqual(len(GRADES),12)
        for grade, config in GRADES.items():
            low, high = config['bounds']
            for count in (low, high):
                self.assertEqual(validate_one(self.article(grade,count)), [])
            for count in (low-1, high+1):
                self.assertTrue(any('词数越界' in e for e in validate_one(self.article(grade,count))))

    def test_unknown_grade_rejected(self):
        data = self.article('k12_g1',40)
        data['grade_id'] = 'k12_g13'
        self.assertIn('grade_id非法',validate_one(data))

if __name__ == '__main__': unittest.main()
