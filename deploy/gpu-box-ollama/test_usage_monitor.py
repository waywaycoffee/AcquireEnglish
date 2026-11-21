import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from usage_monitor import UsageStore, UsageMiddleware, normalize_json_response


class UsageTests(unittest.TestCase):
    def test_repairs_actual_model_json(self):
        raw = '{\n "word": "minecraft",\n tag: "noun",\n "definitionCn": "game"\n}'
        value = json.loads(normalize_json_response(raw))
        self.assertEqual(value['type'], 'noun')
        self.assertEqual(value['word'], 'minecraft')
        self.assertEqual(json.loads(normalize_json_response('```json\n{"ok":true}\n```')), {'ok': True})
        with self.assertRaises(ValueError):
            normalize_json_response('{broken')

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
            store.finish(
                store.begin('another', 'anonymous client', module='oral_coach'), 502, {}
            )
            self.assertEqual(store.snapshot()['failures'], 1)
            self.assertEqual(store.snapshot()['requests_without_usage'], 1)
            mods = {row['module'] for row in store.snapshot()['by_module']}
            self.assertIn('oral_coach', mods)

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
