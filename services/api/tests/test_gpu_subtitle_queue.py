import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from app.services import gpu_subtitle_queue as queue

class QueueTest(unittest.TestCase):
 def setUp(self):
  self.folder=tempfile.TemporaryDirectory()
  self.patch=patch.object(queue,'settings',SimpleNamespace(media_cache_dir=self.folder.name))
  self.patch.start()
 def tearDown(self):
  self.patch.stop()
  self.folder.cleanup()
 def test_duplicate_and_lease(self):
  a=queue.enqueue('BV1CS4y1v7sQ',1)
  b=queue.enqueue('BV1CS4Y1V7SQ',1)
  self.assertEqual(a['id'],b['id'])
  job=queue.claim()
  self.assertIsNone(queue.claim())
  with queue.connection() as db:
   db.execute('UPDATE jobs SET deadline=0 WHERE id=?',(job['id'],))
  replacement=queue.claim()
  with self.assertRaises(ValueError):queue.update(job,'completed')
  queue.update(replacement,'completed')
  self.assertIsNone(queue.claim())
 def test_retry_limit(self):
  queue.enqueue('BV1CS4y1v7sQ',1)
  for _ in range(4):
   queue.update(queue.claim(),'retry')
  self.assertIsNone(queue.claim())
  with queue.connection() as db:
   self.assertEqual(db.execute('SELECT state FROM jobs').fetchone()[0],'failed')
 def test_invalid(self):
  with self.assertRaises(ValueError):queue.enqueue('bad',1)

 SRT='1\n00:00:01,000 --> 00:00:02,500\nHello there.\n\n2\n00:00:03,000 --> 00:00:04,000\nHow are you?\n'

 def test_parse_srt(self):
  cues=queue.parse_srt_cues(self.SRT)
  self.assertEqual([c['text'] for c in cues],['Hello there.','How are you?'])
  self.assertAlmostEqual(cues[0]['start'],1.0)
  self.assertAlmostEqual(cues[0]['end'],2.5)

 def test_translate_jobs_run_before_asr(self):
  queue.enqueue('BV1CS4y1v7sQ',1)
  t=queue.enqueue_translate('BV1CS4y1v7sQ',2,en_srt=self.SRT,title='Ep 2')
  self.assertEqual(t['kind'],'translate')
  job=queue.claim()
  self.assertEqual((job['page'],job['kind'],job['state']),(2,'translate','translating'))
  self.assertIn('Hello there.',job['payload'])

 def test_translate_does_not_replace_pending_asr(self):
  a=queue.enqueue('BV1CS4y1v7sQ',1)
  t=queue.enqueue_translate('BV1CS4y1v7sQ',1,en_srt=self.SRT)
  self.assertEqual((t['id'],t['kind']),(a['id'],'asr'))

 def test_failed_translate_upgrades_to_asr(self):
  queue.enqueue_translate('BV1CS4y1v7sQ',1,en_srt=self.SRT)
  for _ in range(4):
   queue.update(queue.claim(),'retry')
  queue.claim()
  again=queue.enqueue('BV1CS4y1v7sQ',1)
  self.assertEqual((again['kind'],again['state'],again['attempts']),('asr','queued',0))

 def test_translate_rejects_tiny_srt(self):
  with self.assertRaises(ValueError):
   queue.enqueue_translate('BV1CS4y1v7sQ',1,en_srt='1\n00:00:01,000 --> 00:00:02,000\nHi\n')

if __name__=='__main__':unittest.main()
