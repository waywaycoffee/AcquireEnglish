import unittest
from unittest import mock

import backend_health as bh


class BackendHealthTests(unittest.TestCase):
    def test_expect_helpers(self):
        self.assertIsNotNone(bh._expect_status_ok({"status": "down"}))
        self.assertIsNone(bh._expect_status_ok({"status": "ok"}))
        self.assertIsNone(bh._expect_coach_ready({"ready": True}))
        self.assertIsNotNone(bh._expect_coach_ready({"ready": False}))
        self.assertIsNone(bh._expect_stats({"day": "2026-01-01", "requests": 1}))

    def test_collect_counts_critical_unhealthy(self):
        def fake_http(url, **kwargs):
            if "11434" in url:
                return dict(
                    ok=True, state="healthy", http_status=200, latency_ms=10, detail="ok"
                )
            if "11435" in url:
                return dict(
                    ok=True, state="healthy", http_status=200, latency_ms=5, detail="ok"
                )
            if ":8010" in url:
                return dict(
                    ok=False, state="unhealthy", http_status=0, latency_ms=3, detail="down"
                )
            if "/api/health" in url and "/coach/" not in url:
                return dict(
                    ok=True, state="healthy", http_status=200, latency_ms=80, detail="ok"
                )
            if "/coach/" in url:
                return dict(
                    ok=False,
                    state="unhealthy",
                    http_status=502,
                    latency_ms=40,
                    detail="HTTP 502",
                )
            return dict(
                ok=False, state="unhealthy", http_status=0, latency_ms=1, detail="unknown"
            )

        def fake_proc(needle):
            return dict(
                ok=True, state="healthy", http_status=0, latency_ms=20, detail="proc"
            )

        with mock.patch.object(bh, "_http_probe", side_effect=fake_http), mock.patch.object(
            bh, "_windows_process_match", side_effect=fake_proc
        ):
            snap = bh.collect_backend_health(max_workers=4)
        self.assertEqual(snap["overall"], "unhealthy")
        self.assertEqual(snap["counts"]["unhealthy"], 2)
        self.assertEqual(snap["counts"]["critical_unhealthy"], 1)
        self.assertTrue(any(a["service"] == "oral_coach" for a in snap["alerts"]))
        self.assertEqual(snap["services"][0]["id"], "local_llm")


if __name__ == "__main__":
    unittest.main()
