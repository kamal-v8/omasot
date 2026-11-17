#!/usr/bin/env python3
"""Regression tests for the Android-style screen time reminder backend.

Run from the plugin root with:
    python3 -m unittest discover -s tests -v

The state path is redirected to a temp dir so these tests never touch the
user's real screentime.json history.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import tracker  # noqa: E402


def last_json(stream):
    lines = [line for line in stream.getvalue().splitlines() if line.strip()]
    return json.loads(lines[-1])


def call(fn, *args):
    """Run a tracker command and return the JSON payload it printed."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        fn(*args)
    return last_json(out)


class ReminderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        state = os.path.join(self.tmp.name, "screentime.json")
        tracker.STATE_FILE = state
        tracker.LOCK_FILE = state + ".lock"
        tracker.REMINDER_FILE = state + ".reminder"

    # ── settings ──────────────────────────────────────────────────
    def test_defaults_match_android(self):
        payload = call(tracker.print_today)
        self.assertTrue(payload["screen_time_reminders"])
        self.assertEqual(payload["reminder_interval_minutes"], 30)

    def test_toggle_on_off(self):
        self.assertFalse(call(tracker.toggle_reminders)["screen_time_reminders"])
        self.assertTrue(call(tracker.toggle_reminders)["screen_time_reminders"])

    def test_interval_clamped(self):
        self.assertEqual(call(tracker.set_reminder_interval, 999)["reminder_interval_minutes"], 240)
        self.assertEqual(call(tracker.set_reminder_interval, 0)["reminder_interval_minutes"], 1)
        self.assertEqual(call(tracker.set_reminder_interval, 15)["reminder_interval_minutes"], 15)

    # ── reminder publication ─────────────────────────────────────
    def test_no_reminder_by_default(self):
        self.assertEqual(call(tracker.print_reminder), {})

    def test_disabled_publishes_nothing(self):
        tracker.write_reminder_file({"app": "firefox", "app_seconds": 1800,
                                     "interval_minutes": 30, "nonce": 1,
                                     "created": tracker.time.time()})
        call(tracker.toggle_reminders)
        self.assertEqual(call(tracker.print_reminder), {})

    def test_stale_reminder_ignored(self):
        tracker.write_reminder_file({"app": "firefox", "app_seconds": 1800,
                                     "interval_minutes": 30, "nonce": 1,
                                     "created": tracker.time.time() - tracker.REMINDER_MAX_AGE_SECONDS - 1})
        self.assertEqual(call(tracker.print_reminder), {})

    def test_markup_app_name_is_plain(self):
        tracker.write_reminder_file({"app": '<img src="https://evil.invalid/x">',
                                     "app_seconds": 100, "interval_minutes": 30,
                                     "nonce": 7, "created": tracker.time.time()})
        payload = call(tracker.print_reminder)
        self.assertNotIn("<", payload["app"])
        self.assertNotIn(">", payload["app"])

    # ── continuous-use firing ────────────────────────────────────
    def _use_app(self, app, clock, ticks):
        """Advance the mocked clock in 5s steps while `app` stays focused."""
        for _ in range(ticks):
            clock[0] += 5
            call(tracker.tick)

    def test_fires_after_continuous_interval(self):
        call(tracker.set_reminder_interval, 1)
        clock = [1000.0]
        with mock.patch.object(tracker.time, "time", lambda: clock[0]), \
             mock.patch.object(tracker, "probe_presence", return_value=(True, False)), \
             mock.patch.object(tracker, "probe_focused_window", return_value={"class": "firefox"}), \
             mock.patch.object(tracker, "resolve_app", return_value="firefox"):
            self._use_app("firefox", clock, 11)
            self.assertEqual(call(tracker.print_reminder), {})
            self._use_app("firefox", clock, 1)  # 12 * 5s == 60s == interval
            reminder = call(tracker.print_reminder)

        self.assertEqual(reminder["app"], "firefox")
        self.assertEqual(reminder["interval_minutes"], 1)
        self.assertGreaterEqual(reminder["app_seconds"], 60)
        self.assertIsInstance(reminder["nonce"], (int, float))

        # A fresh session: the next reminder gets a different nonce.
        with mock.patch.object(tracker.time, "time", lambda: clock[0]), \
             mock.patch.object(tracker, "probe_presence", return_value=(True, False)), \
             mock.patch.object(tracker, "probe_focused_window", return_value={"class": "firefox"}), \
             mock.patch.object(tracker, "resolve_app", return_value="firefox"):
            self._use_app("firefox", clock, 12)
            second = call(tracker.print_reminder)
        self.assertNotEqual(second["nonce"], reminder["nonce"])

    def test_switching_app_resets_session(self):
        call(tracker.set_reminder_interval, 1)
        clock = [1000.0]
        with mock.patch.object(tracker.time, "time", lambda: clock[0]), \
             mock.patch.object(tracker, "probe_presence", return_value=(True, False)), \
             mock.patch.object(tracker, "probe_focused_window", return_value={"class": "firefox"}):
            with mock.patch.object(tracker, "resolve_app", return_value="firefox"):
                self._use_app("firefox", clock, 10)
            with mock.patch.object(tracker, "resolve_app", return_value="zen"):
                self._use_app("zen", clock, 1)
            with mock.patch.object(tracker, "resolve_app", return_value="firefox"):
                self._use_app("firefox", clock, 1)
            self.assertEqual(call(tracker.print_reminder), {})



if __name__ == "__main__":
    unittest.main()
