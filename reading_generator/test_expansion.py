import unittest
from test_grades import GradeValidationTest
from expand_grades import validate

class ExpansionValidationTest(unittest.TestCase):
    def fixture(self):
        data=GradeValidationTest().article('k12_j1',200)
        for question,kind in zip(data['questions'],['main_idea','detail','inference','vocabulary_attitude']):
            question['evidence_quote']='word word'
            question['question_type']=kind
        return data

    def test_valid_evidence_and_types(self):
        self.assertEqual(validate(self.fixture(),'k12_j1'),[])

    def test_invented_evidence_blocked(self):
        data=self.fixture();data['questions'][0]['evidence_quote']='invented sentence'
        self.assertTrue(any('evidence_quote' in e for e in validate(data,'k12_j1')))

    def test_wrong_grade_and_question_order_blocked(self):
        data=self.fixture();data['questions'][2]['question_type']='detail'
        self.assertTrue(any('题序' in e for e in validate(data,'k12_j1')))
        self.assertIn('年级不匹配',validate(data,'k12_j2'))

if __name__=='__main__':unittest.main()
