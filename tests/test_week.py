#!/usr/bin/env python3
"""Regression tests for Sunday-first weekly grouping."""
import contextlib
import datetime
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import tracker  # noqa: E402


class WeekTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        state = os.path.join(self.tmp.name, "screentime.json")
        tracker.STATE_FILE = state
        tracker.LOCK_FILE = state + ".lock"
        tracker.REMINDER_FILE = state + ".reminder"

    def _cmd(self, fn, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            fn(*args)
        return json.loads(out.getvalue().strip().splitlines()[-1])

    def test_week_starts_on_sunday(self):
        today = datetime.date.today()
        sunday = today - datetime.timedelta(days=(today.weekday() + 1) % 7)
        data = {"_schema": 2}
        for i, seconds in ((0, 3600), (1, 7200), (2, 1800)):
            day = sunday + datetime.timedelta(days=i)
            data[day.isoformat()] = {"09": seconds}
        with open(tracker.STATE_FILE, "w") as f:
            json.dump(data, f)

        payload = self._cmd(tracker.apps_week, 0)

        self.assertEqual(payload["days"][0]["date"], sunday.isoformat())
        self.assertEqual(payload["days"][0]["label"], "Sun")
        self.assertEqual(payload["days"][1]["label"], "Mon")
        self.assertEqual(payload["days"][2]["label"], "Tue")
        self.assertEqual(payload["days"][0]["day_total"], 3600)
        self.assertTrue(payload["week_label"].startswith(sunday.strftime("%b")))

    def test_previous_week_offset(self):
        today = datetime.date.today()
        sunday = today - datetime.timedelta(days=(today.weekday() + 1) % 7)
        previous = sunday - datetime.timedelta(days=7)
        data = {"_schema": 2, previous.isoformat(): {
            "09": 3600, "_apps": {"firefox": 3600},
        }}
        with open(tracker.STATE_FILE, "w") as f:
            json.dump(data, f)

        payload = self._cmd(tracker.apps_week, -1)

        self.assertEqual(payload["days"][0]["date"], previous.isoformat())
        self.assertEqual(payload["days"][0]["day_total"], 3600)
        self.assertEqual(payload["week_total"], 3600)


if __name__ == "__main__":
    unittest.main()
