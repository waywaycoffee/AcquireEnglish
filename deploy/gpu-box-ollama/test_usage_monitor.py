import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from usage_monitor import (
    UsageStore,
    UsageMiddleware,
    normalize_json_response,
    classify_outcome,
    OUTCOME_HTTP_ERROR,
    OUTCOME_CLIENT_ABORT,
    OUTCOME_MISSING_USAGE,
    OUTCOME_OK,
)


class UsageTests(unittest.TestCase):
    def test_repairs_actual_model_json(self):
        raw = '{\n "word": "minecraft",\n tag: "noun",\n "definitionCn": "game"\n}'
        value = json.loads(normalize_json_response(raw))
        self.assertEqual(value['type'], 'noun')
        self.assertEqual(value['word'], 'minecraft')
        self.assertEqual(json.loads(normalize_json_response('```json\n{"ok":true}\n```')), {'ok': True})
        with self.assertRaises(ValueError):
            normalize_json_response('{broken')

    def test_classify_outcome(self):
        self.assertEqual(classify_outcome(200, {'prompt_tokens': 1}), OUTCOME_OK)
        self.assertEqual(classify_outcome(502, {}), OUTCOME_HTTP_ERROR)
        self.assertEqual(classify_outcome(499, {}), OUTCOME_CLIENT_ABORT)
        self.assertEqual(classify_outcome(200, {}), OUTCOME_MISSING_USAGE)

    def test_counts_and_persistence(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'usage.db'
            store = UsageStore(path)
            request_id = store.begin(
                'private-user@example.com', 'anonymous client', module='translation'
            )
            self.assertEqual(store.snapshot()['clients'][0]['in_flight'], 1)
            store.finish(request_id, 200, dict(prompt_tokens=10, completion_tokens=7))
            snap = UsageStore(path).snapshot()
            self.assertEqual(snap['total_tokens'], 17)
            self.assertEqual(snap['active_clients'], 1)
            self.assertEqual(snap['by_module'][0]['module'], 'translation')
            self.assertNotIn('private-user', json.dumps(snap))
            self.assertIn('latency_ms', snap)
            self.assertIn('refreshed_at', snap)
            store.finish(
                store.begin('another', 'anonymous client', module='oral_coach'), 502, {}
            )
            snap2 = store.snapshot()
            self.assertEqual(snap2['failures'], 1)
            self.assertEqual(snap2['true_errors'], 1)
            self.assertEqual(snap2['requests_without_usage'], 1)
            mods = {row['module'] for row in snap2['by_module']}
            self.assertIn('oral_coach', mods)

            # barge-in vs missing usage
            store.finish(
                store.begin('abort', 'anonymous client', module='oral_coach', session='s1'),
                499,
                {},
            )
            store.finish(
                store.begin('miss', 'anonymous client', module='oral_coach'),
                200,
                {},
            )
            snap3 = store.snapshot()
            self.assertEqual(snap3['client_aborts'], 1)
            self.assertEqual(snap3['missing_usage'], 1)
            self.assertGreaterEqual(len(snap3['recent_errors']), 2)
            store.note_remote_scrape('100.1.2.3')
            rev = store.reverse_path_info()
            self.assertTrue(rev['ok'])
            self.assertEqual(rev['age_seconds'], 0)

    def test_middleware_collects_chunked_response_usage(self):
        with tempfile.TemporaryDirectory() as folder:
            store = UsageStore(Path(folder) / 'usage.db')

            async def app(scope, receive, send):
                await send(dict(type='http.response.start', status=200))
                await send(dict(type='http.response.body', body=b'{"usage":{"prompt_tokens":3,', more_body=True))
                await send(dict(type='http.response.body', body=b'"completion_tokens":4}}'))

            async def send(message):
                pass

            asyncio.run(UsageMiddleware(app, store)(dict(type='http', path='/v1/chat/completions', headers=[], client=('127.0.0.1', 1)), None, send))
            self.assertEqual(store.snapshot()['total_tokens'], 7)


if __name__ == '__main__':
    unittest.main()
