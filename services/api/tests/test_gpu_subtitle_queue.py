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
 def test_enqueue_reopens_failed(self):
  queue.enqueue('BV1CS4y1v7sQ',1)
  for _ in range(4):
   queue.update(queue.claim(),'retry')
  self.assertIsNone(queue.claim())
  reopened=queue.enqueue('BV1CS4y1v7sQ',1)
  self.assertEqual(reopened['state'],'queued')
  self.assertEqual(reopened['attempts'],0)
  self.assertIsNotNone(queue.claim())
 def test_invalid(self):
  with self.assertRaises(ValueError):queue.enqueue('bad',1)

if __name__=='__main__':unittest.main()
